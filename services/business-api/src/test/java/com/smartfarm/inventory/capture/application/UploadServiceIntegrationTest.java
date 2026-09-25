package com.smartfarm.inventory.capture.application;

import static org.junit.jupiter.api.Assertions.assertArrayEquals;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import com.smartfarm.inventory.BusinessApiApplication;
import com.smartfarm.inventory.capture.domain.CaptureKind;
import com.smartfarm.inventory.capture.domain.CaptureManifest;
import com.smartfarm.inventory.capture.domain.ManifestAsset;
import com.smartfarm.inventory.capture.domain.ViewPosition;
import com.smartfarm.inventory.capture.infrastructure.StagedObjectStorage;
import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.nio.ByteBuffer;
import java.security.MessageDigest;
import java.time.Instant;
import java.time.LocalDate;
import java.util.HexFormat;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Primary;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.test.context.junit.jupiter.SpringExtension;
import org.testcontainers.containers.MySQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

@SpringBootTest(classes = {BusinessApiApplication.class, UploadServiceIntegrationTest.StorageConfiguration.class},
        properties = {"app.security.enabled=false", "app.object-storage.secret-key=test-secret"})
@Testcontainers(disabledWithoutDocker = true)
class UploadServiceIntegrationTest {
    @Container
    static final MySQLContainer<?> MYSQL = new MySQLContainer<>("mysql:8.4")
            .withDatabaseName("pig_inventory")
            .withUsername("pig_inventory")
            .withPassword("integration-test-password");

    @DynamicPropertySource
    static void datasourceProperties(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url", MYSQL::getJdbcUrl);
        registry.add("spring.datasource.username", MYSQL::getUsername);
        registry.add("spring.datasource.password", MYSQL::getPassword);
    }

    @Autowired
    private UploadService uploadService;

    @Autowired
    private StagedObjectStorage objectStorage;

    @Autowired
    private JdbcTemplate jdbc;

    private UUID organizationId;
    private UUID penId;

    @BeforeEach
    void seedOrganizationAndPen() {
        jdbc.update("DELETE FROM domain_event_outbox");
        jdbc.update("DELETE FROM inference_job");
        jdbc.update("DELETE FROM media_asset");
        jdbc.update("DELETE FROM capture_set");
        jdbc.update("DELETE FROM upload_blob");
        jdbc.update("DELETE FROM upload_package");
        jdbc.update("DELETE FROM inventory_session");
        jdbc.update("DELETE FROM pen");
        jdbc.update("DELETE FROM building");
        jdbc.update("DELETE FROM farm_organization");
        organizationId = UUID.randomUUID();
        UUID buildingId = UUID.randomUUID();
        penId = UUID.randomUUID();
        jdbc.update("INSERT INTO farm_organization (id, code, name) VALUES (?, 'org', 'Organization')", bytes(organizationId));
        jdbc.update("INSERT INTO building (id, organization_id, code, name) VALUES (?, ?, 'b1', 'Building')",
                bytes(buildingId), bytes(organizationId));
        jdbc.update("INSERT INTO pen (id, building_id, code, name) VALUES (?, ?, 'p1', 'Pen')",
                bytes(penId), bytes(buildingId));
    }

    @Test
    void createsUploadsValidatesManifestAndCommitsExactlyOnce() throws Exception {
        UUID clientPackageId = UUID.randomUUID();
        UploadCommand command = new UploadCommand(clientPackageId, organizationId, penId, LocalDate.of(2026, 8, 21), CaptureKind.SINGLE);
        UploadOutcome<UploadPackageView> created = uploadService.createPackage(command, UUID.randomUUID());
        UploadOutcome<UploadPackageView> replayedCreate = uploadService.createPackage(command, UUID.randomUUID());
        assertEquals(false, created.replayed());
        assertEquals(created.body().id(), replayedCreate.body().id());

        byte[] image = "evidence-bytes".getBytes();
        String sha256 = HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(image));
        UUID assetId = UUID.randomUUID();
        UploadOutcome<Void> blob = uploadService.putBlob(created.body().id(), assetId, UUID.randomUUID(), sha256,
                image.length, new ByteArrayInputStream(image));
        assertEquals(false, blob.replayed());
        assertEquals(true, uploadService.putBlob(created.body().id(), assetId, UUID.randomUUID(), sha256,
                image.length, new ByteArrayInputStream(image)).replayed());

        CaptureManifest manifest = new CaptureManifest(UUID.randomUUID(), CaptureKind.SINGLE, penId,
                List.of(new ManifestAsset(assetId, ViewPosition.SINGLE, Instant.parse("2026-08-21T00:00:00Z"),
                        "evidence.jpg", 100, 100, sha256, null, image.length, "image/jpeg", Map.of(), null)));
        assertEquals(false, uploadService.putManifest(created.body().id(), UUID.randomUUID(), manifest).replayed());
        assertEquals(true, uploadService.putManifest(created.body().id(), UUID.randomUUID(), manifest).replayed());

        UploadOutcome<CommitUploadResult> committed = uploadService.commit(created.body().id(), UUID.randomUUID(), "test-correlation");
        UploadOutcome<CommitUploadResult> replayedCommit = uploadService.commit(created.body().id(), UUID.randomUUID(), "test-correlation");
        assertEquals(false, committed.replayed());
        assertEquals(committed.body().sessionId(), replayedCommit.body().sessionId());
        assertEquals(1, count("inventory_session"));
        assertEquals(1, count("media_asset"));
        assertEquals(1, count("inference_job"));
        assertEquals(1, count("domain_event_outbox"));
    }

    @Test
    void concurrentCommitsReturnOneSessionJobAndOutboxEvent() throws Exception {
        byte[] image = "concurrent-evidence".getBytes();
        String sha256 = HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(image));
        UploadOutcome<UploadPackageView> uploadPackage = uploadService.createPackage(
                new UploadCommand(UUID.randomUUID(), organizationId, penId, LocalDate.of(2026, 8, 21), CaptureKind.SINGLE),
                UUID.randomUUID());
        UUID assetId = UUID.randomUUID();
        uploadService.putBlob(uploadPackage.body().id(), assetId, UUID.randomUUID(), sha256, image.length, new ByteArrayInputStream(image));
        uploadService.putManifest(uploadPackage.body().id(), UUID.randomUUID(), new CaptureManifest(
                UUID.randomUUID(), CaptureKind.SINGLE, penId,
                List.of(new ManifestAsset(assetId, ViewPosition.SINGLE, Instant.now(), "image.jpg", 10, 10,
                        sha256, null, image.length, "image/jpeg", Map.of(), null))));

        CountDownLatch start = new CountDownLatch(1);
        try (ExecutorService executor = Executors.newFixedThreadPool(2)) {
            Future<UploadOutcome<CommitUploadResult>> first = executor.submit(() -> {
                start.await(10, TimeUnit.SECONDS);
                return uploadService.commit(uploadPackage.body().id(), UUID.randomUUID(), "test-correlation");
            });
            Future<UploadOutcome<CommitUploadResult>> second = executor.submit(() -> {
                start.await(10, TimeUnit.SECONDS);
                return uploadService.commit(uploadPackage.body().id(), UUID.randomUUID(), "test-correlation");
            });
            start.countDown();
            assertEquals(first.get(10, TimeUnit.SECONDS).body().sessionId(),
                    second.get(10, TimeUnit.SECONDS).body().sessionId());
        }
        assertEquals(1, count("inventory_session"));
        assertEquals(1, count("inference_job"));
        assertEquals(1, count("domain_event_outbox"));
    }

    @Test
    void blocksExactDuplicatesWithinTheOrganizationAtManifest() throws Exception {
        byte[] image = "same-evidence".getBytes();
        String sha256 = HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(image));
        commitSingleImage(image, sha256);
        UploadOutcome<UploadPackageView> second = uploadService.createPackage(
                new UploadCommand(UUID.randomUUID(), organizationId, penId, LocalDate.of(2026, 8, 22), CaptureKind.SINGLE),
                UUID.randomUUID());
        UUID assetId = UUID.randomUUID();
        uploadService.putBlob(second.body().id(), assetId, UUID.randomUUID(), sha256, image.length, new ByteArrayInputStream(image));
        CaptureManifest duplicateManifest = new CaptureManifest(UUID.randomUUID(), CaptureKind.SINGLE, penId,
                List.of(new ManifestAsset(assetId, ViewPosition.SINGLE, Instant.now(), "duplicate.jpg", 10, 10,
                        sha256, null, image.length, "image/jpeg", Map.of(), null)));
        UploadException exception = assertThrows(UploadException.class,
                () -> uploadService.putManifest(second.body().id(), UUID.randomUUID(), duplicateManifest));
        assertEquals("EXACT_DUPLICATE_IMAGE", exception.code());
    }

    @Test
    void blocksReUploadOfADeletedImageWithADistinctConflict() throws Exception {
        byte[] image = "deleted-evidence".getBytes();
        String sha256 = HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(image));
        commitSingleImage(image, sha256);
        jdbc.update("UPDATE media_asset SET state = 'deleted', deleted_at = CURRENT_TIMESTAMP(6) WHERE sha256 = ?", sha256);
        UploadOutcome<UploadPackageView> second = uploadService.createPackage(
                new UploadCommand(UUID.randomUUID(), organizationId, penId, LocalDate.of(2026, 8, 23), CaptureKind.SINGLE),
                UUID.randomUUID());
        UUID assetId = UUID.randomUUID();
        uploadService.putBlob(second.body().id(), assetId, UUID.randomUUID(), sha256, image.length, new ByteArrayInputStream(image));
        CaptureManifest duplicateManifest = new CaptureManifest(UUID.randomUUID(), CaptureKind.SINGLE, penId,
                List.of(new ManifestAsset(assetId, ViewPosition.SINGLE, Instant.now(), "reupload.jpg", 10, 10,
                        sha256, null, image.length, "image/jpeg", Map.of(), null)));
        UploadException exception = assertThrows(UploadException.class,
                () -> uploadService.putManifest(second.body().id(), UUID.randomUUID(), duplicateManifest));
        assertEquals("DELETED_DUPLICATE_IMAGE", exception.code());
    }

    @Test
    void rejectsAnAssetIdentifierAlreadyStoredByAnotherPackageWithoutTouchingCommittedEvidence() throws Exception {
        byte[] image = "committed-evidence-bytes".getBytes();
        String sha256 = sha256Of(image);
        UUID committedAssetId = commitSingleImage(image, sha256);
        String evidenceKey = jdbc.queryForObject("SELECT storage_key FROM media_asset", String.class);
        // 证据键按内容寻址,与客户端可控的 assetId 无关
        assertEquals("evidence/" + organizationId + "/" + sha256, evidenceKey);
        InMemoryStagedObjectStorage storage = (InMemoryStagedObjectStorage) objectStorage;
        assertArrayEquals(image, storage.peek(evidenceKey));

        // 攻击者在另一个 package 复用同一 asset_id,不得覆盖并删除已提交证据
        UploadOutcome<UploadPackageView> second = uploadService.createPackage(
                new UploadCommand(UUID.randomUUID(), organizationId, penId, LocalDate.of(2026, 8, 24), CaptureKind.SINGLE),
                UUID.randomUUID());
        byte[] hostile = "hostile-evidence-bytes".getBytes();
        UploadException exception = assertThrows(UploadException.class,
                () -> uploadService.putBlob(second.body().id(), committedAssetId, UUID.randomUUID(), sha256Of(hostile),
                        hostile.length, new ByteArrayInputStream(hostile)));
        assertEquals("BLOB_IDENTIFIER_REUSED", exception.code());
        assertArrayEquals(image, storage.peek(evidenceKey));
    }

    @Test
    void concurrentReplaysOfOneBlobKeepThePromotedEvidenceObject() throws Exception {
        byte[] image = "replayed-evidence-bytes".getBytes();
        String sha256 = sha256Of(image);
        UploadOutcome<UploadPackageView> uploadPackage = uploadService.createPackage(
                new UploadCommand(UUID.randomUUID(), organizationId, penId, LocalDate.of(2026, 8, 25), CaptureKind.SINGLE),
                UUID.randomUUID());
        UUID assetId = UUID.randomUUID();
        CountDownLatch start = new CountDownLatch(1);
        try (ExecutorService executor = Executors.newFixedThreadPool(2)) {
            Future<UploadOutcome<Void>> first = executor.submit(() -> {
                start.await(10, TimeUnit.SECONDS);
                return uploadService.putBlob(uploadPackage.body().id(), assetId, UUID.randomUUID(), sha256,
                        image.length, new ByteArrayInputStream(image));
            });
            Future<UploadOutcome<Void>> second = executor.submit(() -> {
                start.await(10, TimeUnit.SECONDS);
                return uploadService.putBlob(uploadPackage.body().id(), assetId, UUID.randomUUID(), sha256,
                        image.length, new ByteArrayInputStream(image));
            });
            start.countDown();
            List<Boolean> replays = List.of(
                    first.get(10, TimeUnit.SECONDS).replayed(), second.get(10, TimeUnit.SECONDS).replayed());
            assertEquals(List.of(false, true), replays.stream().sorted().toList());
        }
        // 重放分支不得删除证据键:败者清理的正是胜者已登记的证据对象
        InMemoryStagedObjectStorage storage = (InMemoryStagedObjectStorage) objectStorage;
        String evidenceKey = "evidence/" + organizationId + "/" + sha256;
        assertArrayEquals(image, storage.peek(evidenceKey));
        assertEquals(1, count("upload_blob"));
        assertEquals(evidenceKey, jdbc.queryForObject("SELECT storage_key FROM upload_blob", String.class));
        for (String deleted : storage.deletions()) {
            assertTrue(!deleted.startsWith("evidence/"), "已 promote 的证据键不允许删除: " + deleted);
        }
    }

    @Test
    void concurrentBlobsForOneAssetIdentifierAcrossPackagesNeverDestroyWinningEvidence() throws Exception {
        byte[] firstBytes = "winner-evidence-bytes".getBytes();
        byte[] secondBytes = "loser-evidence-bytes!".getBytes();
        UUID assetId = UUID.randomUUID();
        UploadOutcome<UploadPackageView> first = uploadService.createPackage(
                new UploadCommand(UUID.randomUUID(), organizationId, penId, LocalDate.of(2026, 8, 26), CaptureKind.SINGLE),
                UUID.randomUUID());
        UploadOutcome<UploadPackageView> second = uploadService.createPackage(
                new UploadCommand(UUID.randomUUID(), organizationId, penId, LocalDate.of(2026, 8, 27), CaptureKind.SINGLE),
                UUID.randomUUID());
        CountDownLatch start = new CountDownLatch(1);
        List<Throwable> failures = new java.util.ArrayList<>();
        try (ExecutorService executor = Executors.newFixedThreadPool(2)) {
            List<Future<UploadOutcome<Void>>> attempts = List.of(
                    executor.submit(() -> {
                        start.await(10, TimeUnit.SECONDS);
                        return uploadService.putBlob(first.body().id(), assetId, UUID.randomUUID(), sha256Of(firstBytes),
                                firstBytes.length, new ByteArrayInputStream(firstBytes));
                    }),
                    executor.submit(() -> {
                        start.await(10, TimeUnit.SECONDS);
                        return uploadService.putBlob(second.body().id(), assetId, UUID.randomUUID(), sha256Of(secondBytes),
                                secondBytes.length, new ByteArrayInputStream(secondBytes));
                    }));
            start.countDown();
            for (Future<UploadOutcome<Void>> attempt : attempts) {
                try {
                    attempt.get(10, TimeUnit.SECONDS);
                } catch (ExecutionException exception) {
                    failures.add(exception.getCause());
                }
            }
        }
        // 败者必须被拒,且绝不能删掉胜者的证据对象
        assertEquals(1, failures.size());
        assertEquals("BLOB_IDENTIFIER_REUSED", ((UploadException) failures.getFirst()).code());
        assertEquals(1, count("upload_blob"));
        String storedSha = jdbc.queryForObject("SELECT sha256 FROM upload_blob", String.class);
        String evidenceKey = jdbc.queryForObject("SELECT storage_key FROM upload_blob", String.class);
        assertEquals("evidence/" + organizationId + "/" + storedSha, evidenceKey);
        InMemoryStagedObjectStorage storage = (InMemoryStagedObjectStorage) objectStorage;
        assertArrayEquals(storedSha.equals(sha256Of(firstBytes)) ? firstBytes : secondBytes, storage.peek(evidenceKey));
        for (String deleted : storage.deletions()) {
            assertTrue(!deleted.startsWith("evidence/"), "已 promote 的证据键不允许删除: " + deleted);
        }
    }

    @Test
    void sameContentAcrossPackagesSharesOneEvidenceKeyAndNeverDeletesIt() throws Exception {
        byte[] image = "shared-content-evidence".getBytes();
        String sha256 = sha256Of(image);
        commitSingleImage(image, sha256);
        String evidenceKey = jdbc.queryForObject("SELECT storage_key FROM media_asset", String.class);

        UploadOutcome<UploadPackageView> second = uploadService.createPackage(
                new UploadCommand(UUID.randomUUID(), organizationId, penId, LocalDate.of(2026, 8, 28), CaptureKind.SINGLE),
                UUID.randomUUID());
        UUID otherAssetId = UUID.randomUUID();
        uploadService.putBlob(second.body().id(), otherAssetId, UUID.randomUUID(), sha256,
                image.length, new ByteArrayInputStream(image));
        // 同内容按内容寻址落在同一证据键上,天然幂等
        assertEquals(evidenceKey, jdbc.queryForObject("SELECT storage_key FROM upload_blob WHERE package_id = ?",
                String.class, bytes(second.body().id())));
        InMemoryStagedObjectStorage storage = (InMemoryStagedObjectStorage) objectStorage;
        assertArrayEquals(image, storage.peek(evidenceKey));

        // 业务规则拒绝重复图,失败路径同样不得删除共享的证据对象
        CaptureManifest duplicateManifest = new CaptureManifest(UUID.randomUUID(), CaptureKind.SINGLE, penId,
                List.of(new ManifestAsset(otherAssetId, ViewPosition.SINGLE, Instant.now(), "duplicate.jpg", 10, 10,
                        sha256, null, image.length, "image/jpeg", Map.of(), null)));
        UploadException exception = assertThrows(UploadException.class,
                () -> uploadService.putManifest(second.body().id(), UUID.randomUUID(), duplicateManifest));
        assertEquals("EXACT_DUPLICATE_IMAGE", exception.code());
        assertArrayEquals(image, storage.peek(evidenceKey));
    }

    private UUID commitSingleImage(byte[] image, String sha256) {
        UploadOutcome<UploadPackageView> uploadPackage = uploadService.createPackage(
                new UploadCommand(UUID.randomUUID(), organizationId, penId, LocalDate.of(2026, 8, 21), CaptureKind.SINGLE),
                UUID.randomUUID());
        UUID assetId = UUID.randomUUID();
        uploadService.putBlob(uploadPackage.body().id(), assetId, UUID.randomUUID(), sha256, image.length, new ByteArrayInputStream(image));
        uploadService.putManifest(uploadPackage.body().id(), UUID.randomUUID(), new CaptureManifest(
                UUID.randomUUID(), CaptureKind.SINGLE, penId,
                List.of(new ManifestAsset(assetId, ViewPosition.SINGLE, Instant.now(), "image.jpg", 10, 10,
                        sha256, null, image.length, "image/jpeg", Map.of(), null))));
        uploadService.commit(uploadPackage.body().id(), UUID.randomUUID(), "test-correlation");
        return assetId;
    }

    private static String sha256Of(byte[] image) throws java.security.NoSuchAlgorithmException {
        return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(image));
    }

    private int count(String table) {
        Integer result = jdbc.queryForObject("SELECT COUNT(*) FROM " + table, Integer.class);
        return result == null ? 0 : result;
    }

    private static byte[] bytes(UUID uuid) {
        return ByteBuffer.allocate(16).putLong(uuid.getMostSignificantBits()).putLong(uuid.getLeastSignificantBits()).array();
    }

    @TestConfiguration
    static class StorageConfiguration {
        @Bean
        @Primary
        StagedObjectStorage stagedObjectStorage() {
            return new InMemoryStagedObjectStorage();
        }
    }

    static class InMemoryStagedObjectStorage implements StagedObjectStorage {
        private final Map<String, byte[]> objects = new ConcurrentHashMap<>();
        private final List<String> deletions = java.util.Collections.synchronizedList(new java.util.ArrayList<>());

        @Override
        public String stage(UUID packageId, UUID assetId, InputStream content, long contentLength) {
            try {
                byte[] bytes = content.readAllBytes();
                if (bytes.length != contentLength) {
                    throw new IllegalArgumentException("Unexpected byte count");
                }
                String key = "staging/" + packageId + "/" + assetId + "/" + UUID.randomUUID();
                objects.put(key, bytes);
                return key;
            } catch (IOException exception) {
                throw new IllegalStateException(exception);
            }
        }

        @Override
        public String promote(String stagedKey, UUID organizationId, String sha256) {
            byte[] bytes = objects.remove(stagedKey);
            if (bytes == null) {
                throw new IllegalStateException("Staged object is unavailable");
            }
            String key = "evidence/" + organizationId + "/" + sha256;
            objects.put(key, bytes);
            return key;
        }

        @Override
        public InputStream open(String key) {
            byte[] bytes = objects.get(key);
            if (bytes == null) throw new IllegalArgumentException("Evidence is unavailable");
            return new ByteArrayInputStream(bytes);
        }

        @Override
        public void deleteQuietly(String key) {
            if (key == null) {
                return;
            }
            deletions.add(key);
            objects.remove(key);
        }

        byte[] peek(String key) {
            return objects.get(key);
        }

        List<String> deletions() {
            return deletions;
        }
    }
}
