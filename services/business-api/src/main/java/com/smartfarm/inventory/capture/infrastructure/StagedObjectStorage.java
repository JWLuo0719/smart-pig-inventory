package com.smartfarm.inventory.capture.infrastructure;

import java.io.InputStream;
import java.util.UUID;

public interface StagedObjectStorage {
    String stage(UUID packageId, UUID assetId, InputStream content, long contentLength);

    String promote(String stagedKey, UUID organizationId, UUID assetId);

    /** Opens private evidence only after the business service has authorized the caller. */
    InputStream open(String key);

    void deleteQuietly(String key);
}
