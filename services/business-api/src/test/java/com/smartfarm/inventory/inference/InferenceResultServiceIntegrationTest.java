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
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
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
        properties = {"app.security.enabled=false", "app.object-storage.secret-key=test-secret",
                "app.inference.dispatcher.enabled=false", "app.inference.model-key=test-model",
                "app.inference.model-version=1.0.0",
                "app.inference.model-checksum=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                "app.inference.adapter-version=http-v1"})
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

    @Autowired
    private InferenceJobAdministrationService administrationService;

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
        // This isolated test database can now contain immutable correction lineages.
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

    @Test
    void exposesResearchDetectionsAsASingleImageCandidateCount() throws Exception {
        UUID jobId = committedJob(CaptureKind.SINGLE);

        assertThat(resultService.accept(jobId, reviewRequiredResult(3)))
                .isEqualTo(InferenceResultService.CallbackOutcome.CREATED);

        assertThat(jdbc.queryForObject("SELECT status FROM inference_job WHERE id = ?", String.class, bytes(jobId)))
                .isEqualTo("review_required");
        assertThat(jdbc.queryForObject("SELECT candidate_count FROM inventory_session", Integer.class)).isEqualTo(3);
        UUID sessionId = jdbc.queryForObject("SELECT session_id FROM inference_job WHERE id = ?", this::uuid, bytes(jobId));
        var session = inventoryReviewService.session(sessionId);
        assertThat(session.count()).isEqualTo(3);
        assertThat(session.detections()).hasSize(3);
        assertThat(session.latencyMs()).isEqualTo(12);
        assertThat(session.model().checksum()).isEqualTo("a".repeat(64));
    }

    @Test
    void neverSumsResearchDetectionsAcrossThreeViewEvidence() throws Exception {
        UUID jobId = committedJob(CaptureKind.LEFT_CENTER_RIGHT);

        assertThat(resultService.accept(jobId, reviewRequiredResult(6)))
                .isEqualTo(InferenceResultService.CallbackOutcome.CREATED);

        assertThat(jdbc.queryForObject("SELECT status FROM inference_job WHERE id = ?", String.class, bytes(jobId)))
                .isEqualTo("review_required");
        assertThat(jdbc.queryForObject("SELECT candidate_count FROM inventory_session", Integer.class)).isNull();
    }

    @Test
    void exposesStructuredInferenceFailureForReviewWithoutCreatingABusinessCount() throws Exception {
        UUID jobId = committedJob(CaptureKind.SINGLE);
        InferenceCallbackResult failed = new InferenceCallbackResult(
                "failed", null, List.of(), List.of("Provider timeout; manual review required"),
                "test-model", "1.0.0", "a".repeat(64), "http-v1", "provider-error", 2000,
                "PROVIDER_TIMEOUT", "Counting provider timed out before returning a result");

        assertThat(resultService.accept(jobId, failed)).isEqualTo(InferenceResultService.CallbackOutcome.CREATED);

        UUID sessionId = jdbc.queryForObject("SELECT session_id FROM inference_job WHERE id = ?", this::uuid, bytes(jobId));
        var session = inventoryReviewService.session(sessionId);
        assertThat(session.status()).isEqualTo("review_required");
        assertThat(session.count()).isNull();
        assertThat(session.rawModelCount()).isNull();
        assertThat(session.inferenceStatus()).isEqualTo("failed");
        assertThat(session.failureCode()).isEqualTo("PROVIDER_TIMEOUT");
        assertThat(session.failureMessage()).isEqualTo("Counting provider timed out before returning a result");
        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM inference_result_receipt", Integer.class)).isEqualTo(1);
    }

    @Test
    void createsAnImmutableAuditedRetryAndReplaysTheSameAdministrativeIntent() throws Exception {
        UUID sourceJobId = committedJob(CaptureKind.SINGLE);
        resultService.accept(sourceJobId, failedResult());
        UUID idempotencyKey = UUID.randomUUID();
        String reason = "Provider 已恢复，管理员要求使用原模型身份重试";

        var before = administrationService.failedJobs(Instant.now().plusSeconds(1), 50);
        assertThat(before).singleElement().satisfies(job -> {
            assertThat(job.jobId()).isEqualTo(sourceJobId);
            assertThat(job.retryable()).isTrue();
            assertThat(job.requestedModel().checksum()).isEqualTo("a".repeat(64));
        });

        var created = administrationService.retry(sourceJobId, reason, idempotencyKey, "retry-test");
        var replayed = administrationService.retry(sourceJobId, reason, idempotencyKey, "retry-test");

        assertThat(created.replayed()).isFalse();
        assertThat(replayed.replayed()).isTrue();
        assertThat(replayed.result().retryJobId()).isEqualTo(created.result().retryJobId());
        assertThat(created.result().rootJobId()).isEqualTo(sourceJobId);
        assertThat(created.result().retrySequence()).isEqualTo(1);
        assertThat(created.result().requestedModel().checksum()).isEqualTo("a".repeat(64));
        assertThatThrownBy(() -> administrationService.retry(
                sourceJobId, reason, UUID.randomUUID(), "retry-test"))
                .isInstanceOf(InferenceException.class)
                .hasMessageContaining("already has a successor");

        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM inference_job", Integer.class)).isEqualTo(2);
        assertThat(jdbc.queryForObject("SELECT status FROM inference_job WHERE id = ?", String.class, bytes(sourceJobId)))
                .isEqualTo("failed");
        assertThat(jdbc.queryForObject("SELECT failure_code FROM inference_job WHERE id = ?", String.class, bytes(sourceJobId)))
                .isEqualTo("PROVIDER_TIMEOUT");
        assertThat(jdbc.queryForObject("SELECT requested_model_checksum FROM inference_job WHERE id = ?", String.class,
                bytes(created.result().retryJobId()))).isEqualTo("a".repeat(64));
        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM domain_event_outbox", Integer.class)).isEqualTo(2);
        assertThat(jdbc.queryForObject(
                "SELECT COUNT(*) FROM audit_event WHERE action = 'inference.retry_requested'", Integer.class)).isEqualTo(1);

        var after = administrationService.failedJobs(Instant.now().plusSeconds(1), 50);
        assertThat(after).singleElement().satisfies(job -> {
            assertThat(job.retryable()).isFalse();
            assertThat(job.retryBlockedReason()).isEqualTo("ALREADY_RETRIED");
            assertThat(job.retriedByJobId()).isEqualTo(created.result().retryJobId());
        });
    }

    @Test
    void concurrentAdministrativeReplaysCreateOnlyOneSuccessor() throws Exception {
        UUID sourceJobId = committedJob(CaptureKind.SINGLE);
        resultService.accept(sourceJobId, failedResult());
        UUID idempotencyKey = UUID.randomUUID();
        var executor = Executors.newFixedThreadPool(2);
        try {
            var first = executor.submit(() -> administrationService.retry(
                    sourceJobId, "并发重复点击必须只创建一个后继任务", idempotencyKey, "concurrent-retry"));
            var second = executor.submit(() -> administrationService.retry(
                    sourceJobId, "并发重复点击必须只创建一个后继任务", idempotencyKey, "concurrent-retry"));

            var firstResult = first.get(20, TimeUnit.SECONDS);
            var secondResult = second.get(20, TimeUnit.SECONDS);
            assertThat(firstResult.result().retryJobId()).isEqualTo(secondResult.result().retryJobId());
            assertThat(List.of(firstResult.replayed(), secondResult.replayed())).containsExactlyInAnyOrder(false, true);
            assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM inference_job", Integer.class)).isEqualTo(2);
            assertThat(jdbc.queryForObject(
                    "SELECT COUNT(*) FROM audit_event WHERE action = 'inference.retry_requested'", Integer.class)).isEqualTo(1);
        } finally {
            executor.shutdownNow();
        }
    }

    @Test
    void aLateRetryCallbackCannotDemoteAnAlreadyConfirmedSession() throws Exception {
        UUID sourceJobId = committedJob(CaptureKind.SINGLE);
        resultService.accept(sourceJobId, failedResult());
        var retry = administrationService.retry(sourceJobId, "人工复核并行前再尝试一次服务端推理", UUID.randomUUID(), "late-callback");
        UUID sessionId = jdbc.queryForObject(
                "SELECT session_id FROM inference_job WHERE id = ?", this::uuid, bytes(sourceJobId));

        inventoryReviewService.confirm(sessionId, 11, "现场人员已经完成独立人工复核", UUID.randomUUID(), "manual-first");
        resultService.accept(retry.result().retryJobId(), result("succeeded", 10));

        var session = inventoryReviewService.session(sessionId);
        assertThat(session.status()).isEqualTo("confirmed");
        assertThat(session.count()).isEqualTo(11);
        assertThat(jdbc.queryForObject("SELECT status FROM inventory_session WHERE id = ?", String.class, bytes(sessionId)))
                .isEqualTo("confirmed");
        assertThat(jdbc.queryForObject("SELECT status FROM inference_job WHERE id = ?", String.class,
                bytes(retry.result().retryJobId()))).isEqualTo("succeeded");
    }

    @Test
    void aLateRetryCallbackCannotReopenASupersededEvidenceSession() throws Exception {
        UUID sourceJobId = committedJob(CaptureKind.SINGLE);
        resultService.accept(sourceJobId, failedResult());
        var retry = administrationService.retry(sourceJobId, "Retry before independent manual confirmation", UUID.randomUUID(), "late-corrected");
        UUID sessionId = jdbc.queryForObject(
                "SELECT session_id FROM inference_job WHERE id = ?", this::uuid, bytes(sourceJobId));
        inventoryReviewService.confirm(sessionId, 11, "Independent manual confirmation", UUID.randomUUID(), "confirm");
        var corrected = inventoryReviewService.correct(sessionId, 12, "Independent correction preserves history", UUID.randomUUID(), "correct");

        resultService.accept(retry.result().retryJobId(), result("succeeded", 10));

        assertThat(inventoryReviewService.session(sessionId).status()).isEqualTo("superseded");
        assertThat(inventoryReviewService.session(sessionId).count()).isEqualTo(11);
        assertThat(inventoryReviewService.session(corrected.id()).status()).isEqualTo("confirmed");
        assertThat(inventoryReviewService.session(corrected.id()).count()).isEqualTo(12);
        assertThat(inventoryReviewService.tasks(LocalDate.of(2026, 8, 27)))
                .filteredOn(task -> task.penId().equals(penId)).singleElement()
                .satisfies(task -> assertThat(task.sessionId()).isEqualTo(corrected.id()));
    }

    @Test
    void videoUploadAndCallbackRemainManualEvenWhenProviderClaimsSuccess() throws Exception {
        UUID jobId = committedJob(CaptureKind.VIDEO);
        var claimed = result("succeeded", 99);
        assertThat(resultService.accept(jobId, claimed)).isEqualTo(InferenceResultService.CallbackOutcome.CREATED);
        assertThat(resultService.accept(jobId, claimed)).isEqualTo(InferenceResultService.CallbackOutcome.REPLAYED);
        assertThat(jdbc.queryForObject("SELECT candidate_count FROM inventory_session", Integer.class)).isNull();
        assertThat(jdbc.queryForObject("SELECT status FROM inference_job WHERE id = ?", String.class, bytes(jobId))).isEqualTo("review_required");
        assertThat(jdbc.queryForObject("SELECT content_type FROM media_asset", String.class)).isEqualTo("video/mp4");
    }

    private UUID committedJob(CaptureKind kind) throws Exception {
        return committedJob(kind, null);
    }

    private UUID committedJob(CaptureKind kind, String perceptualHash) throws Exception {
        UploadOutcome<UploadPackageView> created = uploadService.createPackage(
                new UploadCommand(UUID.randomUUID(), organizationId, penId, LocalDate.of(2026, 8, 27), kind), UUID.randomUUID());
        List<ViewPosition> positions = kind == CaptureKind.SINGLE
                ? List.of(ViewPosition.SINGLE)
                : kind == CaptureKind.VIDEO ? List.of(ViewPosition.VIDEO) : List.of(ViewPosition.LEFT, ViewPosition.CENTER, ViewPosition.RIGHT);
        java.util.ArrayList<ManifestAsset> assets = new java.util.ArrayList<>();
        for (ViewPosition position : positions) {
            UUID assetId = UUID.randomUUID();
            byte[] image = ("evidence-" + position.wireValue() + '-' + UUID.randomUUID()).getBytes();
            String sha256 = HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(image));
            uploadService.putBlob(created.body().id(), assetId, UUID.randomUUID(), sha256, image.length, new ByteArrayInputStream(image));
            assets.add(new ManifestAsset(assetId, position, Instant.now(), position.wireValue() + ".jpg", 100, 100, sha256,
                    perceptualHash, image.length, kind == CaptureKind.VIDEO ? "video/mp4" : "image/jpeg", Map.of(), null));
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

    private static InferenceCallbackResult reviewRequiredResult(int detectionCount) {
        List<InferenceCallbackResult.Detection> detections = java.util.stream.IntStream.range(0, detectionCount)
                .mapToObj(index -> new InferenceCallbackResult.Detection(
                        UUID.randomUUID(), List.of(1.0, 2.0, 3.0, 4.0), 0.9, 0))
                .toList();
        return new InferenceCallbackResult("review_required", null, detections, List.of("research result"),
                "test-model", "1.0.0", "a".repeat(64), "http-v1", "research-http-yolo", 12, null, null);
    }

    private static InferenceCallbackResult failedResult() {
        return new InferenceCallbackResult(
                "failed", null, List.of(), List.of("Provider timeout; manual review required"),
                "test-model", "1.0.0", "a".repeat(64), "http-v1", "provider-error", 2000,
                "PROVIDER_TIMEOUT", "Counting provider timed out before returning a result");
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
