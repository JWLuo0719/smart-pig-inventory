package com.smartfarm.inventory.inventory.infrastructure;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.smartfarm.inventory.BusinessApiApplication;
import com.smartfarm.inventory.inventory.application.InventoryException;
import com.smartfarm.inventory.inventory.application.InventoryReviewService;
import java.nio.ByteBuffer;
import java.time.LocalDate;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.testcontainers.containers.MySQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

@SpringBootTest(classes = BusinessApiApplication.class, properties = {
        "app.security.enabled=false",
        "app.object-storage.secret-key=test-secret",
        "app.inference.dispatcher.enabled=false"})
@Testcontainers(disabledWithoutDocker = true)
class InventoryCorrectionIntegrationTest {
    @Container
    static final MySQLContainer<?> MYSQL = new MySQLContainer<>("mysql:8.4")
            .withDatabaseName("pig_inventory").withUsername("pig_inventory").withPassword("integration-test-password");

    @DynamicPropertySource
    static void datasource(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url", MYSQL::getJdbcUrl);
        registry.add("spring.datasource.username", MYSQL::getUsername);
        registry.add("spring.datasource.password", MYSQL::getPassword);
    }

    @Autowired private JdbcTemplate jdbc;
    @Autowired private InventoryReviewService service;

    private UUID organizationId;
    private UUID penId;
    private UUID sourceSessionId;
    private LocalDate businessDate;

    @BeforeEach
    void seed() {
        organizationId = UUID.randomUUID();
        UUID buildingId = UUID.randomUUID();
        penId = UUID.randomUUID();
        sourceSessionId = UUID.randomUUID();
        businessDate = LocalDate.of(2026, 9, 4);
        jdbc.update("INSERT INTO farm_organization (id, code, name) VALUES (?, 'CORRECTION', '更正测试场')",
                bytes(organizationId));
        jdbc.update("INSERT INTO building (id, organization_id, code, name) VALUES (?, ?, 'B01', '育肥栋')",
                bytes(buildingId), bytes(organizationId));
        jdbc.update("INSERT INTO pen (id, building_id, code, name) VALUES (?, ?, 'P01', '一号栏')",
                bytes(penId), bytes(buildingId));
        jdbc.update("""
                INSERT INTO inventory_session
                  (id, pen_id, business_date, status, candidate_count, confirmed_count, version, created_by,
                   confirmed_by, confirmed_at, confirmation_idempotency_key)
                VALUES (?, ?, ?, 'confirmed', 10, 10, 1, 'reviewer-1', 'reviewer-1', CURRENT_TIMESTAMP(6), ?)
                """, bytes(sourceSessionId), bytes(penId), businessDate, UUID.randomUUID().toString());
    }

    @Test
    void createsOneCurrentVersionAndReplaysTheSameCorrectionIntent() {
        UUID idempotencyKey = UUID.randomUUID();

        var created = service.correct(sourceSessionId, 12, "复核遮挡区域后确认应为十二头", idempotencyKey, "corr-1");
        var replayed = service.correct(sourceSessionId, 12, "复核遮挡区域后确认应为十二头", idempotencyKey, "corr-2");

        assertThat(replayed.id()).isEqualTo(created.id());
        assertThat(created.version()).isEqualTo(2);
        assertThat(created.supersedesSessionId()).isEqualTo(sourceSessionId);
        assertThat(created.evidenceSessionId()).isEqualTo(sourceSessionId);
        assertThat(created.count()).isEqualTo(12);
        assertThat(service.dailyReport(businessDate)).singleElement().satisfies(row -> {
            assertThat(row.sessionId()).isEqualTo(created.id());
            assertThat(row.confirmedCount()).isEqualTo(12);
        });
        assertThat(service.aggregateReport(penId, businessDate, businessDate).roundedCount()).isEqualTo(12);
        assertThat(jdbc.queryForObject(
                "SELECT COUNT(*) FROM inventory_session WHERE pen_id = ? AND business_date = ? AND status = 'confirmed'",
                Integer.class, bytes(penId), businessDate)).isEqualTo(1);
        assertThat(jdbc.queryForObject(
                "SELECT status FROM inventory_session WHERE id = ?", String.class, bytes(sourceSessionId)))
                .isEqualTo("superseded");
        assertThat(jdbc.queryForObject(
                "SELECT COUNT(*) FROM audit_event WHERE organization_id = ? AND action = 'inventory.corrected'",
                Integer.class, bytes(organizationId))).isEqualTo(1);

        assertThatThrownBy(() -> service.correct(sourceSessionId, 13,
                "另一项更正意图不得复用旧版本", idempotencyKey, "corr-3"))
                .isInstanceOf(InventoryException.class)
                .hasMessageContaining("already been corrected");
    }

    private static byte[] bytes(UUID id) {
        return ByteBuffer.allocate(16).putLong(id.getMostSignificantBits()).putLong(id.getLeastSignificantBits()).array();
    }
}
