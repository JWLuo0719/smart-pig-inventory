package com.smartfarm.inventory.inventory.infrastructure;

import static org.assertj.core.api.Assertions.assertThat;

import com.smartfarm.inventory.BusinessApiApplication;
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
class InventoryReportExportRepositoryIntegrationTest {
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
    @Autowired private JdbcInventoryReviewRepository repository;
    private UUID firstOrganization;
    private UUID firstPen;
    private UUID secondOrganization;
    private UUID secondPen;

    @BeforeEach
    void seed() {
        firstOrganization = organization("ORG-EXPORT-1", "导出测试组织");
        secondOrganization = organization("ORG-EXPORT-2", "隔离组织");
        firstPen = pen(firstOrganization, "B01", "=1+1", "P01", "确认栏舍");
        secondPen = pen(secondOrganization, "B02", "二号栋", "P02", "隔离栏舍");
    }

    @Test
    void returnsOnlyConfirmedRowsFromTheRequestedOrganizationAndRange() {
        LocalDate date = LocalDate.of(2026, 9, 1);
        session(firstPen, date, "confirmed", 12);
        session(firstPen, date.plusDays(1), "review_required", null);
        session(firstPen, date.plusDays(2), "confirmed", 14);
        session(secondPen, date, "confirmed", 99);

        var rows = repository.listConfirmedForExport(firstOrganization, date, date.plusDays(1), 100);

        assertThat(rows).singleElement().satisfies(row -> {
            assertThat(row.businessDate()).isEqualTo(date);
            assertThat(row.buildingName()).isEqualTo("=1+1");
            assertThat(row.confirmedCount()).isEqualTo(12);
        });
        assertThat(repository.findOrganization(firstOrganization)).get().satisfies(organization ->
                assertThat(organization.name()).isEqualTo("导出测试组织"));
    }

    private UUID organization(String code, String name) {
        UUID id = UUID.randomUUID();
        jdbc.update("INSERT INTO farm_organization (id, code, name) VALUES (?, ?, ?)", bytes(id), code, name);
        return id;
    }

    private UUID pen(UUID organizationId, String buildingCode, String buildingName, String penCode, String penName) {
        UUID buildingId = UUID.randomUUID();
        UUID penId = UUID.randomUUID();
        jdbc.update("INSERT INTO building (id, organization_id, code, name) VALUES (?, ?, ?, ?)",
                bytes(buildingId), bytes(organizationId), buildingCode, buildingName);
        jdbc.update("INSERT INTO pen (id, building_id, code, name) VALUES (?, ?, ?, ?)",
                bytes(penId), bytes(buildingId), penCode, penName);
        return penId;
    }

    private void session(UUID penId, LocalDate date, String status, Integer count) {
        jdbc.update("""
                INSERT INTO inventory_session
                  (id, pen_id, business_date, status, confirmed_count, created_by, confirmed_at)
                VALUES (?, ?, ?, ?, ?, 'integration-test', CASE WHEN ? = 'confirmed' THEN CURRENT_TIMESTAMP(6) ELSE NULL END)
                """, bytes(UUID.randomUUID()), bytes(penId), date, status, count, status);
    }

    private static byte[] bytes(UUID id) {
        return ByteBuffer.allocate(16).putLong(id.getMostSignificantBits()).putLong(id.getLeastSignificantBits()).array();
    }
}
