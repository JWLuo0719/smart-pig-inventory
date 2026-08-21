package com.smartfarm.inventory.capture.application;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.smartfarm.inventory.capture.domain.CaptureManifest;
import com.smartfarm.inventory.capture.domain.UploadPackageState;
import com.smartfarm.inventory.capture.infrastructure.JdbcUploadRepository;
import com.smartfarm.inventory.capture.infrastructure.JdbcUploadRepository.CommittedReferences;
import com.smartfarm.inventory.capture.infrastructure.JdbcUploadRepository.StoredBlob;
import com.smartfarm.inventory.capture.infrastructure.JdbcUploadRepository.StoredPackage;
import com.smartfarm.inventory.capture.infrastructure.StagedObjectStorage;
import java.io.InputStream;
import java.security.DigestInputStream;
import java.security.MessageDigest;
import java.time.Instant;
import java.util.HexFormat;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.support.TransactionTemplate;

@Service
public class UploadService {
    private final JdbcUploadRepository repository;
    private final StagedObjectStorage objectStorage;
    private final UploadActor actor;
    private final ObjectMapper objectMapper;
    private final TransactionTemplate transactions;

    public UploadService(
            JdbcUploadRepository repository,
            StagedObjectStorage objectStorage,
            UploadActor actor,
            ObjectMapper objectMapper,
            TransactionTemplate transactions) {
        this.repository = repository;
        this.objectStorage = objectStorage;
        this.actor = actor;
        this.objectMapper = objectMapper;
        this.transactions = transactions;
    }

    public UploadOutcome<UploadPackageView> createPackage(UploadCommand command, UUID idempotencyKey) {
        actor.assertCanAccess(command.organizationId());
        if (!repository.isEnabledPenInOrganization(command.penId(), command.organizationId())) {
            throw UploadException.invalid("PEN_NOT_AVAILABLE", "The pen is unavailable in the active organization");
        }
        try {
            return requiredTransaction(() -> {
                var byClientId = repository.findByClientPackageId(command.organizationId(), command.clientPackageId());
                var byIdempotencyKey = repository.findByCreateIdempotencyKey(command.organizationId(), idempotencyKey);
                if (byClientId.isPresent()) {
                    assertSameCreateIntent(byClientId.get(), command);
                    if (byIdempotencyKey.isPresent() && !byIdempotencyKey.get().id().equals(byClientId.get().id())) {
                        throw UploadException.conflict("IDEMPOTENCY_KEY_REUSED", "The idempotency key belongs to another package");
                    }
                    return new UploadOutcome<>(view(byClientId.get()), true);
                }
                if (byIdempotencyKey.isPresent()) {
                    assertSameCreateIntent(byIdempotencyKey.get(), command);
                    return new UploadOutcome<>(view(byIdempotencyKey.get()), true);
                }
                StoredPackage uploadPackage = new StoredPackage(
                        UUID.randomUUID(), command.organizationId(), command.penId(), command.clientPackageId(),
                        command.businessDate(), command.captureKind(), UploadPackageState.AWAITING_BLOBS, null, null);
                repository.insertPackage(uploadPackage, idempotencyKey);
                return new UploadOutcome<>(view(uploadPackage), false);
            });
        } catch (DuplicateKeyException conflict) {
            StoredPackage recovered = repository.findByClientPackageId(command.organizationId(), command.clientPackageId())
                    .or(() -> repository.findByCreateIdempotencyKey(command.organizationId(), idempotencyKey))
                    .orElseThrow(() -> conflict);
            assertSameCreateIntent(recovered, command);
            return new UploadOutcome<>(view(recovered), true);
        }
    }

    public UploadPackageView getPackage(UUID packageId) {
        StoredPackage uploadPackage = getVisiblePackage(packageId);
        return view(uploadPackage);
    }

    public UploadOutcome<Void> putBlob(
            UUID packageId, UUID assetId, UUID idempotencyKey, String expectedSha256, long contentLength, InputStream content) {
        validateSha256(expectedSha256);
        if (contentLength <= 0) {
            throw UploadException.invalid("BLOB_LENGTH_INVALID", "A positive Content-Length is required for an upload blob");
        }
        StoredPackage uploadPackage = getVisiblePackage(packageId);
        OptionalBlob existing = existingBlob(uploadPackage, assetId, expectedSha256, contentLength);
        if (existing.present()) {
            return new UploadOutcome<>(null, true);
        }
        if (uploadPackage.state() != UploadPackageState.AWAITING_BLOBS) {
            throw UploadException.conflict("UPLOAD_PACKAGE_NOT_ACCEPTING_BLOBS", "The package no longer accepts new blobs");
        }

        String stagedKey = null;
        String evidenceKey = null;
        try {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            try (DigestInputStream digestingContent = new DigestInputStream(content, digest)) {
                stagedKey = objectStorage.stage(packageId, assetId, digestingContent, contentLength);
            }
            String actualSha256 = HexFormat.of().formatHex(digest.digest());
            if (!expectedSha256.equals(actualSha256)) {
                objectStorage.deleteQuietly(stagedKey);
                throw UploadException.invalid("BLOB_SHA256_MISMATCH", "Blob bytes do not match X-Content-SHA256");
            }
            evidenceKey = objectStorage.promote(stagedKey, uploadPackage.organizationId(), assetId);
            String finalEvidenceKey = evidenceKey;
            return requiredTransaction(() -> {
                StoredPackage locked = visibleLockedPackage(packageId);
                OptionalBlob replay = existingBlob(locked, assetId, expectedSha256, contentLength);
                if (replay.present()) {
                    objectStorage.deleteQuietly(finalEvidenceKey);
                    return new UploadOutcome<>(null, true);
                }
                if (locked.state() != UploadPackageState.AWAITING_BLOBS) {
                    throw UploadException.conflict("UPLOAD_PACKAGE_NOT_ACCEPTING_BLOBS", "The package no longer accepts new blobs");
                }
                repository.insertBlob(packageId, assetId, expectedSha256, contentLength, finalEvidenceKey);
                return new UploadOutcome<>(null, false);
            });
        } catch (UploadException exception) {
            if (evidenceKey != null) {
                objectStorage.deleteQuietly(evidenceKey);
            } else {
                objectStorage.deleteQuietly(stagedKey);
            }
            throw exception;
        } catch (Exception exception) {
            if (evidenceKey != null) {
                objectStorage.deleteQuietly(evidenceKey);
            } else {
                objectStorage.deleteQuietly(stagedKey);
            }
            throw new IllegalStateException("Could not process upload blob", exception);
        }
    }

    public UploadOutcome<Void> putManifest(UUID packageId, UUID idempotencyKey, CaptureManifest manifest) {
        StoredPackage packageBeforeLock = getVisiblePackage(packageId);
        assertManifestMatchesPackage(packageBeforeLock, manifest);
        String manifestJson = json(manifest);
        String manifestSha256 = sha256(manifestJson.getBytes(java.nio.charset.StandardCharsets.UTF_8));
        return requiredTransaction(() -> {
            StoredPackage uploadPackage = visibleLockedPackage(packageId);
            assertManifestMatchesPackage(uploadPackage, manifest);
            if (uploadPackage.state() == UploadPackageState.READY_TO_COMMIT || uploadPackage.state() == UploadPackageState.COMMITTED) {
                if (sameJson(uploadPackage.manifestJson(), manifestJson)) {
                    return new UploadOutcome<>(null, true);
                }
                throw UploadException.conflict("MANIFEST_ALREADY_STORED", "A different manifest has already been stored");
            }
            if (uploadPackage.state() != UploadPackageState.AWAITING_BLOBS) {
                throw UploadException.conflict("UPLOAD_PACKAGE_STATE_INVALID", "The package cannot accept a manifest in its current state");
            }
            for (var asset : manifest.assets()) {
                StoredBlob blob = repository.findBlob(packageId, asset.assetId())
                        .orElseThrow(() -> UploadException.invalid("MANIFEST_BLOB_MISSING", "Manifest references a blob that is not uploaded"));
                if (!blob.uploaded() || !blob.sha256().equals(asset.sha256()) || blob.byteSize() != asset.byteSize()) {
                    throw UploadException.invalid("MANIFEST_BLOB_MISMATCH", "Manifest metadata does not match its uploaded blob");
                }
                if (repository.hasExactDuplicate(uploadPackage.organizationId(), asset.sha256())) {
                    throw UploadException.conflict("EXACT_DUPLICATE_IMAGE", "The image already exists in the active organization");
                }
            }
            repository.storeManifest(packageId, idempotencyKey, manifestJson, manifestSha256);
            return new UploadOutcome<>(null, false);
        });
    }

    public UploadOutcome<CommitUploadResult> commit(UUID packageId, UUID idempotencyKey, String correlationId) {
        getVisiblePackage(packageId);
        return requiredTransaction(() -> {
            StoredPackage uploadPackage = visibleLockedPackage(packageId);
            if (uploadPackage.state() == UploadPackageState.COMMITTED) {
                return new UploadOutcome<>(commitResult(uploadPackage), true);
            }
            if (uploadPackage.state() != UploadPackageState.READY_TO_COMMIT || uploadPackage.manifestJson() == null) {
                throw UploadException.invalid("MANIFEST_REQUIRED", "A validated manifest is required before commit");
            }
            CaptureManifest manifest = readManifest(uploadPackage.manifestJson());
            for (var asset : manifest.assets()) {
                if (repository.hasExactDuplicate(uploadPackage.organizationId(), asset.sha256())) {
                    throw UploadException.conflict("EXACT_DUPLICATE_IMAGE", "The image already exists in the active organization");
                }
            }
            UUID sessionId = UUID.randomUUID();
            UUID jobId = UUID.randomUUID();
            repository.insertInventorySession(sessionId, uploadPackage.penId(), uploadPackage.businessDate(), actor.subjectId());
            repository.insertCaptureSet(manifest.captureSetId(), sessionId, uploadPackage.id(), manifest.captureKind());
            for (var asset : manifest.assets()) {
                StoredBlob blob = repository.findBlob(uploadPackage.id(), asset.assetId())
                        .orElseThrow(() -> UploadException.invalid("MANIFEST_BLOB_MISSING", "A manifest blob disappeared before commit"));
                repository.insertMediaAsset(UUID.randomUUID(), uploadPackage.organizationId(), manifest.captureSetId(), asset, blob.storageKey());
            }
            repository.insertInferenceJob(jobId, sessionId, manifest.captureSetId(), correlationId);
            repository.insertOutbox(UUID.randomUUID(), uploadPackage.id(), correlationId, json(Map.of(
                    "eventVersion", 1,
                    "occurredAt", Instant.now().toString(),
                    "packageId", uploadPackage.id(),
                    "sessionId", sessionId,
                    "inferenceJobId", jobId)));
            repository.markCommitted(uploadPackage.id(), sessionId, idempotencyKey);
            return new UploadOutcome<>(new CommitUploadResult(uploadPackage.id(), sessionId, jobId, "submitted"), false);
        });
    }

    private StoredPackage getVisiblePackage(UUID packageId) {
        StoredPackage uploadPackage = repository.findById(packageId).orElseThrow(UploadException::notFound);
        actor.assertCanAccess(uploadPackage.organizationId());
        return uploadPackage;
    }

    private StoredPackage visibleLockedPackage(UUID packageId) {
        StoredPackage uploadPackage = repository.lockById(packageId).orElseThrow(UploadException::notFound);
        actor.assertCanAccess(uploadPackage.organizationId());
        return uploadPackage;
    }

    private OptionalBlob existingBlob(StoredPackage uploadPackage, UUID assetId, String sha256, long byteSize) {
        return repository.findBlob(uploadPackage.id(), assetId)
                .map(blob -> {
                    if (!blob.sha256().equals(sha256) || blob.byteSize() != byteSize) {
                        throw UploadException.conflict("BLOB_IDENTIFIER_REUSED", "The asset identifier belongs to different bytes");
                    }
                    return new OptionalBlob(true);
                })
                .orElseGet(() -> new OptionalBlob(false));
    }

    private void assertSameCreateIntent(StoredPackage stored, UploadCommand command) {
        if (!stored.organizationId().equals(command.organizationId())
                || !stored.penId().equals(command.penId())
                || !stored.businessDate().equals(command.businessDate())
                || stored.captureKind() != command.captureKind()) {
            throw UploadException.conflict("IDEMPOTENCY_KEY_REUSED", "The package identifier or idempotency key has different request data");
        }
    }

    private void assertManifestMatchesPackage(StoredPackage uploadPackage, CaptureManifest manifest) {
        if (manifest.penId() == null || !uploadPackage.penId().equals(manifest.penId())
                || uploadPackage.captureKind() != manifest.captureKind()) {
            throw UploadException.invalid("MANIFEST_PACKAGE_MISMATCH", "Manifest pen and capture kind must match the package");
        }
    }

    private UploadPackageView view(StoredPackage uploadPackage) {
        return new UploadPackageView(uploadPackage.id(), uploadPackage.clientPackageId(), uploadPackage.state(),
                repository.existingAssetIds(uploadPackage.id()));
    }

    private CommitUploadResult commitResult(StoredPackage uploadPackage) {
        CommittedReferences references = repository.findCommittedReferences(uploadPackage.id())
                .orElseThrow(() -> new IllegalStateException("Committed package has no session and inference job"));
        return new CommitUploadResult(uploadPackage.id(), references.sessionId(), references.inferenceJobId(), "submitted");
    }

    private CaptureManifest readManifest(String manifestJson) {
        try {
            return objectMapper.readValue(manifestJson, CaptureManifest.class);
        } catch (JsonProcessingException exception) {
            throw new IllegalStateException("Stored manifest cannot be read", exception);
        }
    }

    private boolean sameJson(String first, String second) {
        try {
            JsonNode firstNode = objectMapper.readTree(first);
            JsonNode secondNode = objectMapper.readTree(second);
            return firstNode.equals(secondNode);
        } catch (JsonProcessingException exception) {
            throw new IllegalStateException("Stored manifest cannot be compared", exception);
        }
    }

    private String json(Object value) {
        try {
            return objectMapper.writeValueAsString(value);
        } catch (JsonProcessingException exception) {
            throw new IllegalArgumentException("Upload value cannot be serialized", exception);
        }
    }

    private String sha256(byte[] bytes) {
        try {
            return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(bytes));
        } catch (Exception exception) {
            throw new IllegalStateException("SHA-256 is unavailable", exception);
        }
    }

    private void validateSha256(String value) {
        if (value == null || !value.matches("^[a-f0-9]{64}$")) {
            throw UploadException.invalid("BLOB_SHA256_INVALID", "X-Content-SHA256 must be a lowercase SHA-256 hex value");
        }
    }

    private <T> T requiredTransaction(java.util.concurrent.Callable<T> operation) {
        T result = transactions.execute(status -> {
            try {
                return operation.call();
            } catch (RuntimeException exception) {
                throw exception;
            } catch (Exception exception) {
                throw new IllegalStateException(exception);
            }
        });
        if (result == null) {
            throw new IllegalStateException("Upload transaction returned no result");
        }
        return result;
    }

    private record OptionalBlob(boolean present) {
    }
}
