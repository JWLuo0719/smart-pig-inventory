package com.smartfarm.inventory.inference;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.smartfarm.inventory.BusinessApiApplication;
import com.smartfarm.inventory.capture.application.CommitUploadResult;
import com.smartfarm.inventory.capture.application.UploadCommand;
import com.smartfarm.inventory.capture.application.UploadOutcome;
import com.smartfarm.inventory.capture.application.UploadPackageView;
import com.smartfarm.inventory.capture.application.UploadService;
import com.smartfarm.inventory.capture.domain.CaptureKind;
import com.smartfarm.inventory.capture.domain.CaptureManifest;
import com.smartfarm.inventory.capture.domain.ManifestAsset;
import com.smartfarm.inventory.capture.domain.ViewPosition;
import com.smartfarm.inventory.capture.infrastructure.StagedObjectStorage;
import com.smartfarm.inventory.inventory.application.InventoryException;
import com.smartfarm.inventory.inventory.application.InventoryReviewService;
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
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Primary;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.testcontainers.containers.MySQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

@SpringBootTest(classes = {BusinessApiApplication.class, InferenceResultServiceIntegrationTest.StorageConfiguration.class},
        properties = {"app.security.enabled=false", "app.object-storage.secret-key=test-secret", "app.inference.dispatcher.enabled=false"})
@Testcontainers(disabledWithoutDocker = true)
class InferenceResultServiceIntegrationTest {
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
    private InferenceResultService resultService;

    @Autowired
    private JdbcTemplate jdbc;

    @Autowired
    private InventoryReviewService inventoryReviewService;

    private UUID organizationId;
    private UUID penId;

    @BeforeEach
    void seedOrganizationAndPen() {
        jdbc.update("DELETE FROM near_duplicate_review");
        jdbc.update("DELETE FROM audit_event");
        jdbc.update("DELETE FROM inference_result_receipt");
        jdbc.update("DELETE FROM count_result");
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
    void acceptsOneFinalResultAndTreatsAnIdenticalCallbackAsReplay() throws Exception {
        UUID jobId = committedJob(CaptureKind.SINGLE);
        InferenceCallbackResult result = result("succeeded", 7);

        assertThat(resultService.accept(jobId, result)).isEqualTo(InferenceResultService.CallbackOutcome.CREATED);
        assertThat(resultService.accept(jobId, result)).isEqualTo(InferenceResultService.CallbackOutcome.REPLAYED);
        assertThatThrownBy(() -> resultService.accept(jobId, result("succeeded", 8)))
                .isInstanceOf(InferenceException.class)
                .hasMessageContaining("different final result");

        assertThat(jdbc.queryForObject("SELECT status FROM inference_job WHERE id = ?", String.class, bytes(jobId)))
                .isEqualTo("succeeded");
        assertThat(jdbc.queryForObject("SELECT candidate_count FROM inventory_session", Integer.class)).isEqualTo(7);
        assertThat(jdbc.queryForObject("SELECT status FROM inventory_session", String.class)).isEqualTo("review_required");
        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM count_result", Integer.class)).isEqualTo(1);
    }

    @Test
    void createsAReviewRecordForNearPerceptualEvidenceWithoutDeletingEitherMedia() throws Exception {
        committedJob(CaptureKind.SINGLE, "0000000000000000");
        committedJob(CaptureKind.SINGLE, "0000000000000001");

        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM near_duplicate_review WHERE state = 'open'", Integer.class))
                .isEqualTo(1);
        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM media_asset WHERE deleted_at IS NULL", Integer.class))
                .isEqualTo(2);
    }

    @Test
    void confirmsAnInferenceResultLocksItsEvidenceAndWritesOneAuditableDecision() throws Exception {
        UUID jobId = committedJob(CaptureKind.SINGLE);
        resultService.accept(jobId, result("succeeded", 7));
        UUID sessionId = jdbc.queryForObject("SELECT session_id FROM inference_job WHERE id = ?", this::uuid, bytes(jobId));
        UUID confirmationKey = UUID.randomUUID();

        InventoryReviewService.InventorySessionView confirmed = inventoryReviewService.confirm(
                sessionId, 9, "现场遮挡后人工复核确认", confirmationKey, "review-test");
        InventoryReviewService.InventorySessionView replay = inventoryReviewService.confirm(
                sessionId, 9, "现场遮挡后人工复核确认", confirmationKey, "review-test");

        assertThat(confirmed.status()).isEqualTo("confirmed");
        assertThat(confirmed.count()).isEqualTo(9);
        assertThat(confirmed.rawModelCount()).isEqualTo(7);
        assertThat(confirmed.inferenceSource()).isEqualTo("manual");
        assertThat(replay).isEqualTo(confirmed);
        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM media_asset WHERE state = 'locked'", Integer.class)).isEqualTo(1);
        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM audit_event WHERE action = 'inventory.confirmed'", Integer.class))
                .isEqualTo(1);
        assertThatThrownBy(() -> inventoryReviewService.confirm(
                sessionId, 9, "现场遮挡后人工复核确认", UUID.randomUUID(), "review-test"))
                .isInstanceOf(InventoryException.class)
                .hasMessageContaining("already been confirmed");
    }

    @Test
    void neverUsesAnUnvalidatedThreeViewSuccessAsAnAutomaticCount() throws Exception {
        UUID jobId = committedJob(CaptureKind.LEFT_CENTER_RIGHT);

        assertThat(resultService.accept(jobId, result("succeeded", 99))).isEqualTo(InferenceResultService.CallbackOutcome.CREATED);

        assertThat(jdbc.queryForObject("SELECT status FROM inference_job WHERE id = ?", String.class, bytes(jobId)))
                .isEqualTo("review_required");
        assertThat(jdbc.queryForObject("SELECT candidate_count FROM inventory_session", Integer.class)).isNull();
        assertThat(jdbc.queryForObject("SELECT CAST(warnings_json AS CHAR) FROM count_result", String.class))
                .contains("Multi-view inference requires");
    }

    private UUID committedJob(CaptureKind kind) throws Exception {
        return committedJob(kind, null);
    }

    private UUID committedJob(CaptureKind kind, String perceptualHash) throws Exception {
        UploadOutcome<UploadPackageView> created = uploadService.createPackage(
                new UploadCommand(UUID.randomUUID(), organizationId, penId, LocalDate.of(2026, 8, 27), kind), UUID.randomUUID());
        List<ViewPosition> positions = kind == CaptureKind.SINGLE
                ? List.of(ViewPosition.SINGLE)
                : List.of(ViewPosition.LEFT, ViewPosition.CENTER, ViewPosition.RIGHT);
        java.util.ArrayList<ManifestAsset> assets = new java.util.ArrayList<>();
        for (ViewPosition position : positions) {
            UUID assetId = UUID.randomUUID();
            byte[] image = ("evidence-" + position.wireValue() + '-' + UUID.randomUUID()).getBytes();
            String sha256 = HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(image));
            uploadService.putBlob(created.body().id(), assetId, UUID.randomUUID(), sha256, image.length, new ByteArrayInputStream(image));
            assets.add(new ManifestAsset(assetId, position, Instant.now(), position.wireValue() + ".jpg", 100, 100, sha256,
                    perceptualHash, image.length, "image/jpeg", Map.of(), null));
        }
        UUID captureSetId = UUID.randomUUID();
        uploadService.putManifest(created.body().id(), UUID.randomUUID(), new CaptureManifest(captureSetId, kind, penId, assets));
        UploadOutcome<CommitUploadResult> committed = uploadService.commit(created.body().id(), UUID.randomUUID(), "inference-result-test");
        return committed.body().inferenceJobId();
    }

    private static InferenceCallbackResult result(String status, Integer count) {
        return new InferenceCallbackResult(status, count, List.of(), List.of("provider test result"), "test-model", "1.0.0",
                "a".repeat(64), "http-v1", "test-provider", 12, null, null);
    }

    private UUID uuid(java.sql.ResultSet resultSet, int rowNumber) throws java.sql.SQLException {
        byte[] value = resultSet.getBytes("session_id");
        return new UUID(ByteBuffer.wrap(value).getLong(), ByteBuffer.wrap(value).getLong(8));
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
        public InputStream open(String key) {
            byte[] bytes = objects.get(key);
            if (bytes == null) throw new IllegalArgumentException("Evidence is unavailable");
            return new ByteArrayInputStream(bytes);
        }

        @Override
        public void deleteQuietly(String key) {
            objects.remove(key);
        }
    }
}
