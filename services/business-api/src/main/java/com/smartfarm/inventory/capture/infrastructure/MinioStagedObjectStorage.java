package com.smartfarm.inventory.capture.infrastructure;

import io.minio.CopyObjectArgs;
import io.minio.MinioClient;
import io.minio.PutObjectArgs;
import io.minio.RemoveObjectArgs;
import io.minio.CopySource;
import java.io.InputStream;
import java.util.UUID;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

@Component
public class MinioStagedObjectStorage implements StagedObjectStorage {
    private final MinioClient client;
    private final String bucket;

    public MinioStagedObjectStorage(
            @Value("${app.object-storage.endpoint}") String endpoint,
            @Value("${app.object-storage.access-key}") String accessKey,
            @Value("${app.object-storage.secret-key}") String secretKey,
            @Value("${app.object-storage.bucket}") String bucket) {
        this.client = MinioClient.builder().endpoint(endpoint).credentials(accessKey, secretKey).build();
        this.bucket = bucket;
    }

    @Override
    public String stage(UUID packageId, UUID assetId, InputStream content, long contentLength) {
        String key = "staging/" + packageId + "/" + assetId + "/" + UUID.randomUUID();
        try {
            client.putObject(PutObjectArgs.builder()
                    .bucket(bucket)
                    .object(key)
                    .stream(content, contentLength, -1)
                    .contentType("application/octet-stream")
                    .build());
            return key;
        } catch (Exception exception) {
            throw UploadStorageException.writeFailed(exception);
        }
    }

    @Override
    public String promote(String stagedKey, UUID organizationId, UUID assetId) {
        String key = "evidence/" + organizationId + "/" + assetId;
        try {
            client.copyObject(CopyObjectArgs.builder()
                    .bucket(bucket)
                    .object(key)
                    .source(CopySource.builder().bucket(bucket).object(stagedKey).build())
                    .build());
            deleteQuietly(stagedKey);
            return key;
        } catch (Exception exception) {
            throw UploadStorageException.writeFailed(exception);
        }
    }

    @Override
    public void deleteQuietly(String key) {
        if (key == null) {
            return;
        }
        try {
            client.removeObject(RemoveObjectArgs.builder().bucket(bucket).object(key).build());
        } catch (Exception ignored) {
            // An orphan cleanup worker will retry objects that could not be removed here.
        }
    }
}
