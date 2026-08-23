package com.smartfarm.inventory.masterdata.application;

import static org.junit.jupiter.api.Assertions.assertEquals;

import com.smartfarm.inventory.BusinessApiApplication;
import com.smartfarm.inventory.masterdata.domain.MasterDataChanges;
import java.nio.ByteBuffer;
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
        "app.security.enabled=true",
        "app.security.jwt-signing-secret=MDEyMzQ1Njc4OWFiY2RlZjAxMjM0NTY3ODlhYmNkZWY=",
        "app.object-storage.secret-key=test-secret"})
@Testcontainers(disabledWithoutDocker = true)
class MasterDataServiceIntegrationTest {
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
    private MasterDataService service;

    @Autowired
    private JdbcTemplate jdbc;

    private UUID organizationId;

    @BeforeEach
    void seedMasterData() {
        jdbc.update("DELETE FROM master_data_tombstone");
        jdbc.update("DELETE FROM pen");
        jdbc.update("DELETE FROM building");
        jdbc.update("DELETE FROM farm_organization");
        organizationId = UUID.randomUUID();
        UUID otherOrganizationId = UUID.randomUUID();
        UUID buildingId = UUID.randomUUID();
        UUID penId = UUID.randomUUID();
        jdbc.update("INSERT INTO farm_organization (id, code, name, sync_version) VALUES (?, 'alpha', 'Alpha', 5)", bytes(organizationId));
        jdbc.update("INSERT INTO farm_organization (id, code, name, sync_version) VALUES (?, 'other', 'Other', 100)", bytes(otherOrganizationId));
        jdbc.update("INSERT INTO building (id, organization_id, code, name, sync_version) VALUES (?, ?, 'b1', 'Building', 7)",
                bytes(buildingId), bytes(organizationId));
        jdbc.update("INSERT INTO pen (id, building_id, code, name, sync_version) VALUES (?, ?, 'p1', 'Pen', 9)",
                bytes(penId), bytes(buildingId));
        jdbc.update("""
                INSERT INTO master_data_tombstone (id, organization_id, entity_type, entity_id, sync_version)
                VALUES (?, ?, 'pen', ?, 10)
                """, bytes(UUID.randomUUID()), bytes(organizationId), bytes(UUID.randomUUID()));
    }

    @Test
    void firstSyncIsFullAndNeverLeaksAnotherOrganization() {
        MasterDataChanges changes = service.changes(organizationId, null);

        assertEquals("10", changes.cursor());
        assertEquals(true, changes.fullResyncRequired());
        assertEquals(1, changes.organizations().size());
        assertEquals("alpha", changes.organizations().getFirst().code());
        assertEquals(1, changes.buildings().size());
        assertEquals(1, changes.pens().size());
        assertEquals(1, changes.deletedEntities().size());
    }

    @Test
    void incrementalSyncReturnsOnlyChangesAfterCursorAndInvalidCursorForcesFullResync() {
        MasterDataChanges incremental = service.changes(organizationId, "7");
        assertEquals(false, incremental.fullResyncRequired());
        assertEquals(0, incremental.organizations().size());
        assertEquals(0, incremental.buildings().size());
        assertEquals(1, incremental.pens().size());
        assertEquals(1, incremental.deletedEntities().size());

        MasterDataChanges invalid = service.changes(organizationId, "unknown");
        assertEquals(true, invalid.fullResyncRequired());
        assertEquals(1, invalid.organizations().size());
    }

    private static byte[] bytes(UUID uuid) {
        return ByteBuffer.allocate(16).putLong(uuid.getMostSignificantBits()).putLong(uuid.getLeastSignificantBits()).array();
    }
}
