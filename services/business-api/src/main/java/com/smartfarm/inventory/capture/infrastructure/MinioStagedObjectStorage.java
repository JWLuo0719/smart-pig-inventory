package com.smartfarm.inventory.capture.infrastructure;

import io.minio.CopyObjectArgs;
import io.minio.GetObjectArgs;
import io.minio.MinioClient;
import io.minio.PutObjectArgs;
import io.minio.RemoveObjectArgs;
import io.minio.CopySource;
import io.minio.errors.ErrorResponseException;
import java.io.ByteArrayInputStream;
import java.io.InputStream;
import java.util.Optional;
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
    public InputStream open(String key) {
        try {
            return client.getObject(GetObjectArgs.builder().bucket(bucket).object(key).build());
        } catch (Exception exception) {
            throw UploadStorageException.readFailed(exception);
        }
    }

    @Override
    public Optional<InputStream> openDerived(String key) {
        try {
            return Optional.of(client.getObject(GetObjectArgs.builder().bucket(bucket).object(key).build()));
        } catch (ErrorResponseException exception) {
            if ("NoSuchKey".equals(exception.errorResponse().code())) return Optional.empty();
            throw UploadStorageException.readFailed(exception);
        } catch (Exception exception) {
            throw UploadStorageException.readFailed(exception);
        }
    }

    @Override
    public void putDerivedJpeg(String key, byte[] content) {
        if (!key.startsWith("thumbnails/v1/")) throw new IllegalArgumentException("Invalid derivative namespace");
        try (var input = new ByteArrayInputStream(content)) {
            client.putObject(PutObjectArgs.builder().bucket(bucket).object(key)
                    .stream(input, content.length, -1).contentType("image/jpeg").build());
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
