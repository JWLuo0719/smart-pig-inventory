package com.smartfarm.inventory.inventory.application;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import com.smartfarm.inventory.BusinessApiApplication;
import com.smartfarm.inventory.capture.infrastructure.StagedObjectStorage;
import com.smartfarm.inventory.inventory.application.InventoryReviewService.InventorySessionView;
import java.nio.ByteBuffer;
import java.sql.Timestamp;
import java.time.LocalDate;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.autoconfigure.SpringBootApplication;
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

@SpringBootTest(classes = {BusinessApiApplication.class, InventoryConfirmIntegrationTest.StorageConfiguration.class},
        properties = {"app.security.enabled=false", "app.object-storage.secret-key=test-secret"})
@Testcontainers(disabledWithoutDocker = true)
class InventoryConfirmIntegrationTest {
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
    private InventoryReviewService reviewService;

    @Autowired
    private JdbcTemplate jdbc;

    private UUID organizationId;
    private UUID penId;
    private final LocalDate businessDate = LocalDate.of(2026, 9, 19);

    @BeforeEach
    void seedOrganizationPenAndSessions() {
        jdbc.update("DELETE FROM audit_event");
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
        insertSession("review_required", 28);
        insertSession("review_required", 20);
        insertSession("submitted", null);
    }

    private void insertSession(String status, Integer candidateCount) {
        jdbc.update("""
                INSERT INTO inventory_session (id, pen_id, business_date, status, candidate_count, created_by)
                VALUES (?, ?, ?, ?, ?, 'local-dev')
                """, bytes(UUID.randomUUID()), bytes(penId), Timestamp.valueOf(businessDate.atStartOfDay()), status,
                candidateCount);
    }

    @Test
    void confirmingArchivesStalePendingSiblingsWithAudit() {
        UUID target = firstSessionId("review_required", 28);
        InventorySessionView confirmed = reviewService.confirm(target, 20, "现场两人独立清点后确认数量", UUID.randomUUID(), "test-correlation");
        assertEquals("confirmed", confirmed.status());
        assertEquals(20, confirmed.count());

        Integer archived = jdbc.queryForObject(
                "SELECT COUNT(*) FROM inventory_session WHERE status = 'superseded'", Integer.class);
        assertEquals(2, archived);
        Integer audits = jdbc.queryForObject(
                "SELECT COUNT(*) FROM audit_event WHERE action = 'inventory.auto_superseded'", Integer.class);
        assertEquals(2, audits);
        String reason = jdbc.queryForObject(
                "SELECT reason FROM audit_event WHERE action = 'inventory.auto_superseded' LIMIT 1", String.class);
        assertTrue(reason.contains("证据保留"));
    }

    @Test
    void confirmingTwiceForTheSamePenAndDateIsRejected() {
        UUID target = firstSessionId("review_required", 28);
        reviewService.confirm(target, 20, "现场两人独立清点后确认数量", UUID.randomUUID(), "test-correlation");
        // 自动归档后，同栏当天不再有任何可确认会话；重复确认同一会话（不同幂等键）被拒绝。
        assertThrows(InventoryException.class,
                () -> reviewService.confirm(target, 20, "重复确认触发护栏拒绝", UUID.randomUUID(), "test-correlation"));
        Integer confirmable = jdbc.queryForObject(
                "SELECT COUNT(*) FROM inventory_session WHERE status IN ('submitted', 'review_required')",
                Integer.class);
        assertEquals(0, confirmable);
    }

    private UUID firstSessionId(String status, Integer candidateCount) {
        return jdbc.queryForObject(
                "SELECT id FROM inventory_session WHERE status = ? AND candidate_count "
                        + (candidateCount == null ? "IS NULL" : "= ?") + " LIMIT 1",
                (resultSet, rowNumber) -> fromBytes(resultSet.getBytes("id")),
                candidateCount == null ? new Object[] {status} : new Object[] {status, candidateCount});
    }

    private static byte[] bytes(UUID value) {
        return ByteBuffer.allocate(16)
                .putLong(value.getMostSignificantBits())
                .putLong(value.getLeastSignificantBits())
                .array();
    }

    private static UUID fromBytes(byte[] bytes) {
        ByteBuffer buffer = ByteBuffer.wrap(bytes);
        return new UUID(buffer.getLong(), buffer.getLong());
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
        public String stage(UUID packageId, UUID assetId, java.io.InputStream content, long contentLength) {
            try {
                byte[] data = content.readAllBytes();
                String key = "staged/" + packageId + "/" + assetId;
                objects.put(key, data);
                return key;
            } catch (java.io.IOException exception) {
                throw new IllegalStateException(exception);
            }
        }

        @Override
        public String promote(String stagedKey, UUID organizationId, UUID assetId) {
            String key = "evidence/" + organizationId + "/" + assetId;
            objects.put(key, objects.get(stagedKey));
            return key;
        }

        @Override
        public java.io.InputStream open(String storageKey) {
            byte[] data = objects.get(storageKey);
            if (data == null) {
                throw new IllegalStateException("Missing staged object " + storageKey);
            }
            return new java.io.ByteArrayInputStream(data);
        }

        @Override
        public void deleteQuietly(String storageKey) {
            objects.remove(storageKey);
        }
    }
}
