package com.smartfarm.inventory.inference;

import static org.assertj.core.api.Assertions.assertThat;

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
import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.nio.ByteBuffer;
import java.security.MessageDigest;
import java.time.Duration;
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

@SpringBootTest(classes = {BusinessApiApplication.class, InferenceStaleJobReaperIntegrationTest.StorageConfiguration.class},
        properties = {"app.security.enabled=false", "app.object-storage.secret-key=test-secret",
                "app.inference.dispatcher.enabled=false", "app.inference.stale-job-timeout=PT24H",
                "app.inference.stale-job-reaper.fixed-delay=3600000"})
@Testcontainers(disabledWithoutDocker = true)
class InferenceStaleJobReaperIntegrationTest {
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
    private InferenceJobAdministrationService administrationService;

    @Autowired
    private JdbcInferenceRepository repository;

    @Autowired
    private JdbcTemplate jdbc;

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
        jdbc.update("""
                UPDATE inventory_session SET supersedes_session_id = NULL, evidence_session_id = NULL,
                    correction_idempotency_key = NULL, correction_reason = NULL
                """);
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
    void reapsTimedOutJobsIntoTheFailedListAndTheRetryChannel() throws Exception {
        UUID jobId = committedJob();
        backdate(jobId, 25);

        new InferenceStaleJobReaper(repository, Duration.ofHours(24)).reapStaleJobs();

        assertThat(statusOf(jobId)).isEqualTo("failed");
        assertThat(jdbc.queryForObject("SELECT failure_code FROM inference_job WHERE id = ?", String.class, bytes(jobId)))
                .isEqualTo("INFERENCE_TIMEOUT");
        assertThat(jdbc.queryForObject("SELECT finished_at IS NULL FROM inference_job WHERE id = ?", Boolean.class, bytes(jobId)))
                .isFalse();
        assertThat(jdbc.queryForObject("SELECT status FROM inventory_session", String.class)).isEqualTo("review_required");
        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM audit_event WHERE action = 'inference.job_timeout'", Integer.class))
                .isEqualTo(1);

        // 超时回收后必须出现在既有失败列表,并且可走管理端重试
        assertThat(administrationService.failedJobs(Instant.now().plusSeconds(1), 50))
                .singleElement().satisfies(job -> {
                    assertThat(job.jobId()).isEqualTo(jobId);
                    assertThat(job.failureCode()).isEqualTo("INFERENCE_TIMEOUT");
                    assertThat(job.retryable()).isTrue();
                });
        var retry = administrationService.retry(jobId, "回收后必须能走管理端重试通道", UUID.randomUUID(), "reaper-test");
        assertThat(retry.replayed()).isFalse();
        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM inference_job", Integer.class)).isEqualTo(2);
    }

    @Test
    void keepsJobsInsideTheTimeoutWindowUntouched() throws Exception {
        UUID jobId = committedJob();

        new InferenceStaleJobReaper(repository, Duration.ofHours(24)).reapStaleJobs();

        assertThat(statusOf(jobId)).isEqualTo("submitted");
        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM audit_event WHERE action = 'inference.job_timeout'", Integer.class))
                .isZero();
    }

    @Test
    void neverTouchesTerminalJobs() throws Exception {
        UUID succeededJob = committedJob();
        resultService.accept(succeededJob, result("succeeded", 7));
        UUID failedJob = committedJob();
        resultService.accept(failedJob, failedResult());
        backdate(succeededJob, 25);
        backdate(failedJob, 25);

        new InferenceStaleJobReaper(repository, Duration.ofHours(24)).reapStaleJobs();

        assertThat(statusOf(succeededJob)).isEqualTo("succeeded");
        assertThat(statusOf(failedJob)).isEqualTo("failed");
        assertThat(jdbc.queryForObject("SELECT failure_code FROM inference_job WHERE id = ?", String.class, bytes(failedJob)))
                .isEqualTo("PROVIDER_TIMEOUT");
        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM audit_event WHERE action = 'inference.job_timeout'", Integer.class))
                .isZero();
    }

    @Test
    void isDisabledWhenTheTimeoutIsZero() throws Exception {
        UUID jobId = committedJob();
        backdate(jobId, 25);

        new InferenceStaleJobReaper(repository, Duration.ZERO).reapStaleJobs();

        assertThat(statusOf(jobId)).isEqualTo("submitted");
        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM audit_event WHERE action = 'inference.job_timeout'", Integer.class))
                .isZero();
    }

    private UUID committedJob() throws Exception {
        UploadOutcome<UploadPackageView> created = uploadService.createPackage(
                new UploadCommand(UUID.randomUUID(), organizationId, penId, LocalDate.of(2026, 8, 27), CaptureKind.SINGLE),
                UUID.randomUUID());
        UUID assetId = UUID.randomUUID();
        byte[] image = ("evidence-" + UUID.randomUUID()).getBytes();
        String sha256 = HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(image));
        uploadService.putBlob(created.body().id(), assetId, UUID.randomUUID(), sha256, image.length, new ByteArrayInputStream(image));
        uploadService.putManifest(created.body().id(), UUID.randomUUID(), new CaptureManifest(
                UUID.randomUUID(), CaptureKind.SINGLE, penId,
                List.of(new ManifestAsset(assetId, ViewPosition.SINGLE, Instant.now(), "image.jpg", 100, 100, sha256,
                        null, image.length, "image/jpeg", Map.of(), null))));
        UploadOutcome<CommitUploadResult> committed = uploadService.commit(created.body().id(), UUID.randomUUID(), "reaper-test");
        return committed.body().inferenceJobId();
    }

    private void backdate(UUID jobId, int hours) {
        jdbc.update("UPDATE inference_job SET created_at = DATE_SUB(CURRENT_TIMESTAMP(6), INTERVAL " + hours
                + " HOUR) WHERE id = ?", bytes(jobId));
    }

    private String statusOf(UUID jobId) {
        return jdbc.queryForObject("SELECT status FROM inference_job WHERE id = ?", String.class, bytes(jobId));
    }

    private static InferenceCallbackResult result(String status, Integer count) {
        return new InferenceCallbackResult(status, count, List.of(), List.of("provider test result"), "test-model", "1.0.0",
                "a".repeat(64), "http-v1", "test-provider", 12, null, null);
    }

    private static InferenceCallbackResult failedResult() {
        return new InferenceCallbackResult(
                "failed", null, List.of(), List.of("Provider timeout; manual review required"),
                "test-model", "1.0.0", "a".repeat(64), "http-v1", "provider-error", 2000,
                "PROVIDER_TIMEOUT", "Counting provider timed out before returning a result");
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
            objects.remove(key);
        }
    }
}
