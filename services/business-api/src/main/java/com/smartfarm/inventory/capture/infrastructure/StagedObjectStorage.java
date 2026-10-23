package com.smartfarm.inventory.capture.infrastructure;

import java.io.InputStream;
import java.util.Optional;
import java.util.UUID;

public interface StagedObjectStorage {
    String stage(UUID packageId, UUID assetId, InputStream content, long contentLength);

    String promote(String stagedKey, UUID organizationId, UUID assetId);

    /** Opens private evidence only after the business service has authorized the caller. */
    InputStream open(String key);

    /** Missing derived objects may be rebuilt; other storage failures must remain visible. */
    default Optional<InputStream> openDerived(String key) {
        return Optional.of(open(key));
    }

    /** Writes a private, replaceable JPEG derivative, never an original evidence object. */
    default void putDerivedJpeg(String key, byte[] content) {
        throw UploadStorageException.writeFailed(new UnsupportedOperationException("Derived storage is not configured"));
    }

    void deleteQuietly(String key);
}
