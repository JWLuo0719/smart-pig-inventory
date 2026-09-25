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
import org.springframework.context.ApplicationContext;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Primary;
import org.springframework.http.client.ClientHttpRequestFactory;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.scheduling.concurrent.ThreadPoolTaskScheduler;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.test.context.DynamicPropertySource;
import org.testcontainers.containers.MySQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

@SpringBootTest(classes = {BusinessApiApplication.class, InferenceOutboxDispatchIntegrationTest.StorageConfiguration.class},
        properties = {"app.security.enabled=false", "app.object-storage.secret-key=test-secret",
                "app.inference.dispatcher.enabled=false"})
@Testcontainers(disabledWithoutDocker = true)
class InferenceOutboxDispatchIntegrationTest {
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
    private JdbcInferenceRepository repository;

    @Autowired
    private ApplicationContext applicationContext;

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
    void dispatchRunsOnAnIsolatedSchedulerAndATimeBoxedHttpClient() {
        // 派发调度池独立于共享 taskScheduler(poolSize=1),且 HTTP 调用必须带超时
        assertThat(applicationContext.containsBean("inferenceDispatchScheduler")).isTrue();
        ThreadPoolTaskScheduler scheduler = applicationContext.getBean("inferenceDispatchScheduler", ThreadPoolTaskScheduler.class);
        // getPoolSize() 是当前存活线程数,配置容量要看核心线程数
        assertThat(scheduler.getScheduledThreadPoolExecutor().getCorePoolSize()).isEqualTo(2);
        assertThat(scheduler.getThreadNamePrefix()).isEqualTo("inference-dispatch-");

        assertThat(applicationContext.containsBean("inferenceRequestFactory")).isTrue();
        ClientHttpRequestFactory requestFactory =
                applicationContext.getBean("inferenceRequestFactory", ClientHttpRequestFactory.class);
        assertThat(requestFactory).isInstanceOf(SimpleClientHttpRequestFactory.class);
        SimpleClientHttpRequestFactory factory = (SimpleClientHttpRequestFactory) requestFactory;
        // SimpleClientHttpRequestFactory 无超时 getter,直接断言字段值
        assertThat(ReflectionTestUtils.getField(factory, "connectTimeout")).isEqualTo(5_000);
        assertThat(ReflectionTestUtils.getField(factory, "readTimeout")).isEqualTo(60_000);
    }

    @Test
    void markPublishedAndMarkRetryOnlyApplyToTheCurrentLeaseAttempt() throws Exception {
        UUID jobId = committedJob();
        JdbcInferenceRepository.DispatchableJob claimed = repository.claimNext(Duration.ofMinutes(5)).orElseThrow();
        assertThat(claimed.jobId()).isEqualTo(jobId);
        assertThat(claimed.attempt()).isEqualTo(1);

        // 租约被他方回收(attempt 序号已递增)后,旧实例的派发结果与重试结果都不得落地
        repository.markRetry(claimed.eventId(), claimed.attempt() + 1, 5, "stale-instance");
        repository.markPublished(claimed.eventId(), claimed.attempt() + 1, claimed.jobId());
        assertThat(outboxState()).isEqualTo("DISPATCHING");
        assertThat(jdbc.queryForObject("SELECT last_error IS NULL FROM domain_event_outbox", Boolean.class)).isTrue();
        assertThat(statusOf(jobId)).isEqualTo("submitted");

        // 当前 attempt 的派发结果正常落地(delaySeconds=0 便于立刻重新认领)
        repository.markRetry(claimed.eventId(), claimed.attempt(), 0, "transient error");
        assertThat(outboxState()).isEqualTo("PENDING");
        assertThat(jdbc.queryForObject("SELECT last_error FROM domain_event_outbox", String.class)).isEqualTo("transient error");

        JdbcInferenceRepository.DispatchableJob reclaimed = repository.claimNext(Duration.ofMinutes(5)).orElseThrow();
        assertThat(reclaimed.attempt()).isEqualTo(2);
        repository.markPublished(reclaimed.eventId(), reclaimed.attempt(), reclaimed.jobId());
        assertThat(outboxState()).isEqualTo("PUBLISHED");
        assertThat(statusOf(jobId)).isEqualTo("processing");
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
        UploadOutcome<CommitUploadResult> committed = uploadService.commit(created.body().id(), UUID.randomUUID(), "dispatch-test");
        return committed.body().inferenceJobId();
    }

    private String outboxState() {
        return jdbc.queryForObject("SELECT state FROM domain_event_outbox", String.class);
    }

    private String statusOf(UUID jobId) {
        return jdbc.queryForObject("SELECT status FROM inference_job WHERE id = ?", String.class, bytes(jobId));
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
