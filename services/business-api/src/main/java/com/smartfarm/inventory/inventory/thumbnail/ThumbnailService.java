package com.smartfarm.inventory.inventory.thumbnail;

import com.smartfarm.inventory.capture.infrastructure.StagedObjectStorage;
import com.smartfarm.inventory.capture.infrastructure.UploadStorageException;
import com.smartfarm.inventory.inventory.application.InventoryException;
import com.smartfarm.inventory.inventory.infrastructure.SecurityReviewActor;
import com.smartfarm.inventory.inventory.thumbnail.JdbcThumbnailRepository.Source;
import java.io.IOException;
import java.io.InputStream;
import java.util.Objects;
import java.util.Optional;
import java.util.UUID;
import java.util.concurrent.Semaphore;
import org.springframework.stereotype.Service;

@Service
public class ThumbnailService {
    public static final int MAX_CONCURRENT_GENERATIONS = 2;
    private final JdbcThumbnailRepository repository;
    private final StagedObjectStorage storage;
    private final ThumbnailCodec codec;
    private final SecurityReviewActor actor;
    private final Semaphore generations = new Semaphore(MAX_CONCURRENT_GENERATIONS);

    public ThumbnailService(JdbcThumbnailRepository repository, StagedObjectStorage storage, ThumbnailCodec codec,
                            SecurityReviewActor actor) {
        this.repository = repository;
        this.storage = storage;
        this.codec = codec;
        this.actor = actor;
    }

    /** No surrounding transaction: storage/decoding cannot retain database locks or connections. */
    public byte[] thumbnail(UUID assetId) {
        UUID organization = actor.activeOrganizationId();
        Source source = authorized(organization, assetId);
        if (!ThumbnailCodec.supported(source.contentType()) || source.byteSize() < 1
                || source.byteSize() > ThumbnailCodec.MAX_SOURCE_BYTES || source.sha256() == null
                || !source.sha256().matches("[a-f0-9]{64}")) throw ThumbnailException.unsupported();
        String key = "thumbnails/v1/" + organization + "/" + assetId + "/" + source.sha256() + "-320.jpg";
        try {
            if (key.equals(source.thumbnailKey())) {
                Optional<InputStream> existing = storage.openDerived(key);
                if (existing.isPresent()) {
                    try (InputStream input = existing.get()) {
                        byte[] cached = input.readNBytes(ThumbnailCodec.MAX_THUMBNAIL_BYTES + 1);
                        if (codec.validCached(cached)) {
                            assertUnchanged(source);
                            return cached;
                        }
                    }
                }
            }
            if (!generations.tryAcquire()) throw ThumbnailException.unavailable();
            try {
                assertUnchanged(source);
                byte[] jpeg;
                try (InputStream input = storage.open(source.storageKey())) {
                    jpeg = codec.create(input, source.contentType());
                }
                assertUnchanged(source);
                storage.putDerivedJpeg(key, jpeg);
                if (!repository.attach(source, key)) throw InventoryException.notFound();
                assertUnchanged(source);
                return jpeg;
            } finally { generations.release(); }
        } catch (IOException | UploadStorageException exception) {
            throw ThumbnailException.unavailable();
        }
    }

    private Source authorized(UUID organization, UUID assetId) {
        if (!organization.equals(actor.activeOrganizationId())) throw InventoryException.notFound();
        actor.assertCanView(organization);
        return repository.find(organization, assetId).orElseThrow(InventoryException::notFound);
    }

    private void assertUnchanged(Source original) {
        Source current = authorized(original.organizationId(), original.assetId());
        if (!Objects.equals(original.sha256(), current.sha256())
                || !Objects.equals(original.storageKey(), current.storageKey())
                || !Objects.equals(original.contentType(), current.contentType())
                || original.byteSize() != current.byteSize()) throw InventoryException.notFound();
    }
}
