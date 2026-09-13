package com.smartfarm.inventory.observability;

import static org.assertj.core.api.Assertions.assertThat;
import com.smartfarm.inventory.BusinessApiApplication;
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
        "app.security.enabled=false", "app.object-storage.secret-key=synthetic",
        "app.inference.dispatcher.enabled=false", "app.monitoring.snapshot-delay-ms=3600000"})
@Testcontainers(disabledWithoutDocker = true)
class BusinessMetricsSnapshotIntegrationTest {
    @Container static final MySQLContainer<?> MYSQL = new MySQLContainer<>("mysql:8.4")
            .withDatabaseName("pig_inventory").withUsername("pig_inventory").withPassword("synthetic");
    @DynamicPropertySource static void datasource(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url", MYSQL::getJdbcUrl);
        registry.add("spring.datasource.username", MYSQL::getUsername);
        registry.add("spring.datasource.password", MYSQL::getPassword);
    }
    @Autowired JdbcTemplate jdbc;
    @Autowired BusinessMetricsSnapshotRepository repository;

    @Test void snapshotReadsRealSchemaAndOnlyCountsRelevantOutstandingEvents() {
        assertThat(repository.read()).hasSize(15).allSatisfy((key, value) -> assertThat(value).isZero());
        jdbc.update("""
                INSERT INTO domain_event_outbox (id, aggregate_type, aggregate_id, event_type, payload_json, correlation_id, state, created_at)
                VALUES (UUID_TO_BIN(UUID()), 'capture', 'synthetic', 'capture_package.committed.v1', '{}', 'synthetic', 'PENDING', CURRENT_TIMESTAMP - INTERVAL 10 MINUTE),
                (UUID_TO_BIN(UUID()), 'other', 'synthetic', 'unrelated.v1', '{}', 'synthetic', 'PENDING', CURRENT_TIMESTAMP - INTERVAL 1 DAY)
                """);
        var first = repository.read();
        assertThat(first.get("pig.inference.outbox.pending")).isEqualTo(1);
        assertThat(first.get("pig.inference.outbox.oldest.seconds")).isBetween(600.0, 610.0);
        assertThat(repository.read().get("pig.inference.outbox.pending")).isEqualTo(1);
        jdbc.update("UPDATE domain_event_outbox SET state='PUBLISHED' WHERE event_type='capture_package.committed.v1'");
        assertThat(repository.read().get("pig.inference.outbox.pending")).isZero();
    }
}
