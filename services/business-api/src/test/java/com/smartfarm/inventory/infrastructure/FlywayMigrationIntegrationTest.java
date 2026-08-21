package com.smartfarm.inventory.infrastructure;

import static org.junit.jupiter.api.Assertions.assertEquals;

import java.sql.Connection;
import java.sql.ResultSet;
import java.sql.Statement;
import org.flywaydb.core.Flyway;
import org.junit.jupiter.api.Test;
import org.testcontainers.containers.MySQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

@Testcontainers(disabledWithoutDocker = true)
class FlywayMigrationIntegrationTest {
    @Container
    static final MySQLContainer<?> MYSQL = new MySQLContainer<>("mysql:8.4")
            .withDatabaseName("pig_inventory")
            .withUsername("pig_inventory")
            .withPassword("integration-test-password");

    @Test
    void appliesBaselineIdentityAndUploadChainMigrations() throws Exception {
        Flyway.configure()
                .dataSource(MYSQL.getJdbcUrl(), MYSQL.getUsername(), MYSQL.getPassword())
                .locations("classpath:db/migration")
                .load()
                .migrate();

        try (Connection connection = MYSQL.createConnection("");
                Statement statement = connection.createStatement()) {
            try (ResultSet migrations = statement.executeQuery(
                    "SELECT COUNT(*) FROM flyway_schema_history WHERE success = 1")) {
                migrations.next();
                assertEquals(3, migrations.getInt(1));
            }
            try (ResultSet userTable = statement.executeQuery(
                    "SELECT COUNT(*) FROM information_schema.tables "
                            + "WHERE table_schema = 'pig_inventory' AND table_name = 'app_user'")) {
                userTable.next();
                assertEquals(1, userTable.getInt(1));
            }
            try (ResultSet timezone = statement.executeQuery(
                    "SELECT COUNT(*) FROM information_schema.columns "
                            + "WHERE table_schema = 'pig_inventory' AND table_name = 'farm_organization' "
                            + "AND column_name = 'timezone_id'")) {
                timezone.next();
                assertEquals(1, timezone.getInt(1));
            }
            try (ResultSet idempotency = statement.executeQuery(
                    "SELECT COUNT(*) FROM information_schema.columns "
                            + "WHERE table_schema = 'pig_inventory' AND table_name = 'upload_package' "
                            + "AND column_name IN ('manifest_idempotency_key', 'manifest_sha256', 'commit_idempotency_key')")) {
                idempotency.next();
                assertEquals(3, idempotency.getInt(1));
            }
        }
    }
}
