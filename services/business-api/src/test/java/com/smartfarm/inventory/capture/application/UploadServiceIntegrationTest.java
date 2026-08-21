package com.smartfarm.inventory.capture.application;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;

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

    private void commitSingleImage(byte[] image, String sha256) {
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

        @Override
        public String stage(UUID packageId, UUID assetId, InputStream content, long contentLength) {
            try {
                byte[] bytes = content.readAllBytes();
                if (bytes.length != contentLength) {
                    throw new IllegalArgumentException("Unexpected byte count");
                }
                String key = "staging/" + packageId + "/" + assetId;
                objects.put(key, bytes);
                return key;
            } catch (IOException exception) {
                throw new IllegalStateException(exception);
            }
        }

        @Override
        public String promote(String stagedKey, UUID organizationId, UUID assetId) {
            byte[] bytes = objects.remove(stagedKey);
            String key = "evidence/" + organizationId + "/" + assetId;
            objects.put(key, bytes);
            return key;
        }

        @Override
        public void deleteQuietly(String key) {
            objects.remove(key);
        }
    }
}
