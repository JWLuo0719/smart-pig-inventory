package com.smartfarm.inventory.capture.infrastructure;

import java.io.InputStream;
import java.util.UUID;

public interface StagedObjectStorage {
    String stage(UUID packageId, UUID assetId, InputStream content, long contentLength);

    String promote(String stagedKey, UUID organizationId, UUID assetId);

    void deleteQuietly(String key);
}
