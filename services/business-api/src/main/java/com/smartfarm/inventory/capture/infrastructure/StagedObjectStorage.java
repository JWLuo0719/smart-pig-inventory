package com.smartfarm.inventory.capture.infrastructure;

import java.io.InputStream;
import java.util.UUID;

public interface StagedObjectStorage {
    String stage(UUID packageId, UUID assetId, InputStream content, long contentLength);

    /**
     * 证据对象键按内容寻址(evidence/{org}/{sha256}):同内容天然幂等,
     * 客户端可控的 assetId 不参与键,无法覆盖或顶替已提交证据。
     */
    String promote(String stagedKey, UUID organizationId, String sha256);

    /** Opens private evidence only after the business service has authorized the caller. */
    InputStream open(String key);

    /** 仅允许删除本次 staged 键;已 promote 的证据键属于共享内容,任何清理路径都不得删除。 */
    void deleteQuietly(String key);
}
