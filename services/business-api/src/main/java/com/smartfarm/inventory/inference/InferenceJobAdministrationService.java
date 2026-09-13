package com.smartfarm.inventory.inference;

import com.smartfarm.inventory.inference.JdbcInferenceAdministrationRepository.FailedJobRow;
import com.smartfarm.inventory.inference.JdbcInferenceAdministrationRepository.LockedJobRow;
import com.smartfarm.inventory.inference.JdbcInferenceAdministrationRepository.RetryChildRow;
import com.smartfarm.inventory.inventory.infrastructure.SecurityReviewActor;
import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class InferenceJobAdministrationService {
    private final JdbcInferenceAdministrationRepository repository;
    private final SecurityReviewActor actor;

    public InferenceJobAdministrationService(
            JdbcInferenceAdministrationRepository repository,
            SecurityReviewActor actor) {
        this.repository = repository;
        this.actor = actor;
    }

    @Transactional(readOnly = true)
    public List<FailedInferenceJobView> failedJobs(Instant before, int limit) {
        UUID organizationId = actor.activeOrganizationId();
        actor.assertCanManageInference(organizationId);
        return repository.listFailed(organizationId, before, limit).stream().map(this::view).toList();
    }

    @Transactional
    public RetryOutcome retry(UUID sourceJobId, String reason, UUID idempotencyKey, String correlationId) {
        LockedJobRow source = repository.lockJob(sourceJobId).orElseThrow(InferenceException::notFound);
        actor.assertCanManageInference(source.organizationId());
        String normalizedReason = normalizeReason(reason);
        if (!"failed".equals(source.status())) {
            throw InferenceException.retryConflict("Only a terminal failed inference job can be retried");
        }

        RetryChildRow existing = repository.findRetryChild(source.id()).orElse(null);
        if (existing != null) {
            if (idempotencyKey.toString().equals(existing.idempotencyKey())
                    && normalizedReason.equals(existing.reason())) {
                return new RetryOutcome(retryResult(source, existing.id(), existing.retrySequence(), true), true);
            }
            throw InferenceException.retryConflict(
                    "This failed inference attempt already has a successor; retry the latest failed attempt instead");
        }
        if (!"review_required".equals(source.sessionStatus())) {
            throw InferenceException.retryConflict(
                    "The inventory session is no longer awaiting review and cannot start another inference attempt");
        }
        var media = repository.lockMedia(source.captureSetId());
        if (media.isEmpty() || media.stream().anyMatch(item -> item.deleted()
                || item.storageKey() == null || item.storageKey().isBlank())) {
            throw InferenceException.retryConflict("The original inference media is no longer fully available");
        }

        UUID retryJobId = UUID.randomUUID();
        String subjectId = actor.subjectId();
        repository.insertRetryJob(retryJobId, source, idempotencyKey, normalizedReason, subjectId, correlationId);
        repository.insertRetryOutbox(UUID.randomUUID(), retryJobId, source.id(), correlationId, Instant.now());
        repository.insertAudit(source.organizationId(), subjectId, source.id(), normalizedReason,
                failureSnapshot(source), retrySnapshot(source, retryJobId), correlationId);
        return new RetryOutcome(retryResult(source, retryJobId, source.retrySequence() + 1, false), false);
    }

    private FailedInferenceJobView view(FailedJobRow row) {
        String blockedReason = retryBlockedReason(row);
        return new FailedInferenceJobView(
                row.id(), row.rootJobId(), row.retryOfJobId(), row.retriedByJobId(), row.sessionId(),
                row.captureSetId(), row.status(), row.retrySequence(), row.failureCode(), row.failureMessage(),
                model(row.requestedModelKey(), row.requestedModelVersion(), row.requestedModelChecksum(),
                        row.requestedAdapterVersion()),
                row.providerKey(), blockedReason == null, blockedReason,
                instant(row.startedAt()), instant(row.finishedAt()), row.createdAt().toString());
    }

    private static String retryBlockedReason(FailedJobRow row) {
        if (row.retriedByJobId() != null) return "ALREADY_RETRIED";
        if (!"review_required".equals(row.sessionStatus())) return "SESSION_NOT_REVIEWABLE";
        if (row.mediaCount() == 0 || row.unavailableMediaCount() > 0) return "MEDIA_UNAVAILABLE";
        return null;
    }

    private static RetryResult retryResult(LockedJobRow source, UUID retryJobId, int retrySequence, boolean replayed) {
        return new RetryResult(source.id(), retryJobId, source.rootJobId(), retrySequence, "submitted", replayed,
                model(source.requestedModelKey(), source.requestedModelVersion(), source.requestedModelChecksum(),
                        source.requestedAdapterVersion()));
    }

    private static ModelIdentity model(String key, String version, String checksum, String adapterVersion) {
        return new ModelIdentity(key, version, checksum, adapterVersion);
    }

    private static Map<String, Object> failureSnapshot(LockedJobRow source) {
        Map<String, Object> snapshot = new LinkedHashMap<>();
        snapshot.put("jobId", source.id().toString());
        snapshot.put("status", source.status());
        snapshot.put("failureCode", source.failureCode());
        snapshot.put("failureMessage", source.failureMessage());
        snapshot.put("retrySequence", source.retrySequence());
        snapshot.put("requestedModel", model(source.requestedModelKey(), source.requestedModelVersion(),
                source.requestedModelChecksum(), source.requestedAdapterVersion()));
        return snapshot;
    }

    private static Map<String, Object> retrySnapshot(LockedJobRow source, UUID retryJobId) {
        return Map.of(
                "sourceJobId", source.id().toString(),
                "retryJobId", retryJobId.toString(),
                "rootJobId", source.rootJobId().toString(),
                "retrySequence", source.retrySequence() + 1,
                "status", "submitted",
                "mediaRetained", true);
    }

    private static String normalizeReason(String reason) {
        if (reason == null || reason.isBlank()) {
            throw InferenceException.retryInvalid("An administrative inference retry requires a reason");
        }
        String normalized = reason.trim();
        if (normalized.length() < 8 || normalized.length() > 500) {
            throw InferenceException.retryInvalid("A retry reason must contain between 8 and 500 characters");
        }
        return normalized;
    }

    private static String instant(Instant value) {
        return value == null ? null : value.toString();
    }

    public record FailedInferenceJobView(
            UUID jobId, UUID rootJobId, UUID retryOfJobId, UUID retriedByJobId, UUID sessionId,
            UUID captureSetId, String status, int retrySequence, String failureCode, String failureMessage,
            ModelIdentity requestedModel, String providerKey, boolean retryable, String retryBlockedReason,
            String startedAt, String finishedAt, String createdAt) {
    }

    public record RetryResult(
            UUID sourceJobId, UUID retryJobId, UUID rootJobId, int retrySequence, String status,
            boolean replayed, ModelIdentity requestedModel) {
    }

    public record ModelIdentity(String modelKey, String version, String checksum, String adapterVersion) {
    }

    public record RetryOutcome(RetryResult result, boolean replayed) {
    }
}
