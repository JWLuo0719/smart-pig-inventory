package com.smartfarm.inventory.masterdata.application;

import static org.junit.jupiter.api.Assertions.*;
import com.smartfarm.inventory.BusinessApiApplication;
import com.smartfarm.inventory.inventory.application.InventoryException;
import com.smartfarm.inventory.masterdata.application.MasterDataAdministrationService.Command;
import java.nio.ByteBuffer;
import java.util.UUID;
import java.util.concurrent.Executors;
import org.junit.jupiter.api.*;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.testcontainers.containers.MySQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

@SpringBootTest(classes = BusinessApiApplication.class, properties = {
    "app.security.enabled=true", "app.security.jwt-signing-secret=MDEyMzQ1Njc4OWFiY2RlZjAxMjM0NTY3ODlhYmNkZWY=",
    "app.object-storage.secret-key=test-secret"})
@Testcontainers(disabledWithoutDocker = true)
class MasterDataAdministrationIntegrationTest {
    @Container static final MySQLContainer<?> MYSQL = new MySQLContainer<>("mysql:8.4")
            .withDatabaseName("pig_inventory").withUsername("pig_inventory").withPassword("integration-test-password");
    @DynamicPropertySource static void properties(DynamicPropertyRegistry r) {
        r.add("spring.datasource.url", MYSQL::getJdbcUrl); r.add("spring.datasource.username", MYSQL::getUsername);
        r.add("spring.datasource.password", MYSQL::getPassword);
    }
    @Autowired MasterDataAdministrationService service;
    @Autowired MasterDataService sync;
    @Autowired JdbcTemplate jdbc;
    @Autowired com.smartfarm.inventory.inventory.application.InventoryReviewService inventory;
    UUID org;
    String subject;
    @BeforeEach void setup() {
        org = UUID.randomUUID(); subject = UUID.randomUUID().toString();
        jdbc.update("INSERT INTO farm_organization(id,code,name,sync_version) VALUES(?,?,?,1)", bytes(org), org.toString(), "Test farm");
        jdbc.update("INSERT INTO organization_membership(id,organization_id,subject_id,role_key) VALUES(?,?,?,'FARM_ADMIN')",
                bytes(UUID.randomUUID()), bytes(org), subject);
        authenticate();
    }
    @AfterEach void cleanup() { SecurityContextHolder.clearContext(); }
    void authenticate() {
        SecurityContextHolder.getContext().setAuthentication(new JwtAuthenticationToken(Jwt.withTokenValue("test")
            .header("alg", "none").subject(subject).claim("active_organization_id", org.toString()).build()));
    }
    @Test void maintainsHierarchyWithReplayAuditAndIncrementalSync() {
        UUID building = UUID.randomUUID(); UUID key = UUID.randomUUID();
        Command create = new Command(org, " B1 ", " First ", true, 0, " create ");
        var first = service.save("buildings", building, key, create, "test");
        assertEquals(first, service.save("buildings", building, key, create, "test"));
        assertEquals(2, first.syncVersion());
        assertEquals("B1", first.code());
        assertEquals(1, jdbc.queryForObject("SELECT COUNT(*) FROM audit_event WHERE organization_id=?", Integer.class, bytes(org)));
        UUID pen = UUID.randomUUID();
        var p = service.save("pens", pen, UUID.randomUUID(), new Command(building, "P1", "Pen", true, 0, "create"), "test");
        assertEquals(3, p.syncVersion());
        assertEquals(1, sync.changes(org, "2").pens().size());
        assertEquals(0, sync.changes(org, "2").buildings().size());
        assertEquals(409, assertThrows(InventoryException.class, () -> service.save("buildings", building, UUID.randomUUID(),
            new Command(org, "B1", "First", false, 2, "disable"), "test")).status());
        service.save("pens", pen, UUID.randomUUID(), new Command(building, "P1", "Pen", false, 3, "disable"), "test");
        service.save("buildings", building, UUID.randomUUID(), new Command(org, "B1", "First", false, 2, "disable"), "test");
        assertFalse(sync.changes(org, "3").pens().getFirst().enabled());
        assertFalse(sync.changes(org, "3").buildings().getFirst().enabled());
        assertEquals(409, assertThrows(InventoryException.class, () -> service.save("pens", pen, UUID.randomUUID(),
            new Command(building, "P1", "Pen", true, 3, "stale"), "test")).status());
    }
    @Test void rejectsForeignParentOperatorDuplicateCodesAndChangedIdempotencyPayload() {
        UUID building = UUID.randomUUID(); UUID key = UUID.randomUUID();
        service.save("buildings", building, key, new Command(org, "B1", "First", true, 0, "create"), "test");
        assertEquals(409, assertThrows(InventoryException.class, () -> service.save("buildings", building, key,
            new Command(org, "B2", "First", true, 0, "create"), "test")).status());
        assertEquals(409, assertThrows(InventoryException.class, () -> service.save("buildings", UUID.randomUUID(), UUID.randomUUID(),
            new Command(org, "B1", "Duplicate", true, 0, "create"), "test")).status());
        assertEquals(404, assertThrows(InventoryException.class, () -> service.save("pens", UUID.randomUUID(), UUID.randomUUID(),
            new Command(UUID.randomUUID(), "P1", "Foreign", true, 0, "create"), "test")).status());
        jdbc.update("UPDATE organization_membership SET role_key='OPERATOR' WHERE organization_id=?", bytes(org));
        assertEquals(404, assertThrows(InventoryException.class, () -> service.save("buildings", UUID.randomUUID(), UUID.randomUUID(),
            new Command(org, "B2", "Denied", true, 0, "create"), "test")).status());
        assertEquals(1, jdbc.queryForObject("SELECT COUNT(*) FROM master_data_command WHERE organization_id=?", Integer.class, bytes(org)));
    }
    @Test void concurrentSameIntentCreatesOneEntityAndAudit() throws Exception {
        UUID id = UUID.randomUUID(); UUID key = UUID.randomUUID();
        Command command = new Command(org, "B1", "Concurrent", true, 0, "create");
        try (var executor = Executors.newFixedThreadPool(2)) {
            java.util.concurrent.Callable<Object> task = () -> { authenticate(); try {
                return service.save("buildings", id, key, command, "test");
            } finally { SecurityContextHolder.clearContext(); } };
            var first = executor.submit(task); var second = executor.submit(task);
            assertEquals(first.get(), second.get());
        }
        assertEquals(1, jdbc.queryForObject("SELECT COUNT(*) FROM audit_event WHERE organization_id=?", Integer.class, bytes(org)));
    }

    @Test void galleryFiltersByDateAndOrganizationAndDeletionPreventsConfirmation() {
        var ids = seedEvidence();
        var date = java.time.LocalDate.of(2026, 9, 12);
        var rows = inventory.mediaLibrary(date, ids[0], 0, 50);
        assertEquals(1, rows.size());
        assertEquals(ids[2], rows.getFirst().assetId());
        assertFalse(rows.getFirst().locked());
        assertEquals(0, inventory.mediaLibrary(date.minusDays(1), null, 0, 50).size());
        assertEquals(0, inventory.mediaLibrary(date, ids[0], 1, 50).size());
        assertEquals(404, assertThrows(InventoryException.class, () -> inventory.mediaLibrary(date, UUID.randomUUID(), 0, 50)).status());
        assertEquals(422, assertThrows(InventoryException.class, () -> inventory.mediaLibrary(date, null, 0, 101)).status());
        UUID deleteKey = UUID.randomUUID();
        inventory.deleteUnlockedEvidence(ids[2], deleteKey, "test");
        inventory.deleteUnlockedEvidence(ids[2], deleteKey, "test");
        assertTrue(inventory.mediaLibrary(date, null, 0, 50).getFirst().deleted());
        assertEquals(409, assertThrows(InventoryException.class, () -> inventory.confirm(ids[1], 19, "人工核对这份测试证据", UUID.randomUUID(), "test")).status());
        assertEquals("review_required", inventory.session(ids[1]).status());
        assertEquals(1, jdbc.queryForObject("SELECT COUNT(*) FROM audit_event WHERE organization_id=? AND action='media.deleted'", Integer.class, bytes(org)));
    }

    @Test void confirmedTaskRemainsCurrentWhenAnotherReviewSessionIsNewer() {
        var ids = seedEvidence();
        var date = java.time.LocalDate.of(2026, 9, 12);
        inventory.confirm(ids[1], 19, "人工核对测试照片十九头", UUID.randomUUID(), "test");
        UUID later = UUID.randomUUID();
        jdbc.update("INSERT INTO inventory_session(id,pen_id,business_date,status,created_by,updated_at) VALUES(?,?,?,'review_required','test',DATE_ADD(NOW(),INTERVAL 1 HOUR))", bytes(later),bytes(ids[0]),date);
        assertEquals(ids[1],inventory.tasks(date).getFirst().sessionId());
        assertEquals("confirmed",inventory.tasks(date).getFirst().status());
        assertTrue(inventory.mediaLibrary(date,null,0,50).getFirst().locked());
        assertEquals(409,assertThrows(InventoryException.class,()->inventory.deleteUnlockedEvidence(ids[2],UUID.randomUUID(),"test")).status());
    }

    private UUID[] seedEvidence() {
        UUID building=UUID.randomUUID(), pen=UUID.randomUUID(), session=UUID.randomUUID(), pack=UUID.randomUUID(), capture=UUID.randomUUID(), asset=UUID.randomUUID();
        service.save("buildings",building,UUID.randomUUID(),new Command(org,"B1","Building",true,0,"create"),"test");
        service.save("pens",pen,UUID.randomUUID(),new Command(building,"P1","Pen",true,0,"create"),"test");
        jdbc.update("INSERT INTO inventory_session(id,pen_id,business_date,status,candidate_count,created_by) VALUES(?,?,'2026-09-12','review_required',19,'test')",bytes(session),bytes(pen));
        jdbc.update("INSERT INTO upload_package(id,organization_id,pen_id,session_id,client_package_id,business_date,capture_kind,idempotency_key,state) VALUES(?,?,?,?,?,'2026-09-12','single',?,'committed')",bytes(pack),bytes(org),bytes(pen),bytes(session),bytes(UUID.randomUUID()),UUID.randomUUID().toString());
        jdbc.update("INSERT INTO capture_set(id,session_id,upload_package_id,client_capture_id,kind) VALUES(?,?,?,?,'single')",bytes(capture),bytes(session),bytes(pack),bytes(UUID.randomUUID()));
        jdbc.update("INSERT INTO upload_blob(asset_id,package_id,sha256,byte_size,content_type,storage_key,uploaded_at) VALUES(?,?,?,3,'image/jpeg','synthetic-test',NOW())",bytes(asset),bytes(pack),"a".repeat(64));
        jdbc.update("INSERT INTO media_asset(id,organization_id,capture_set_id,asset_id,view_position,original_name,content_type,byte_size,sha256,storage_key,state) VALUES(?,?,?,?,'single','synthetic.jpg','image/jpeg',3,?,'synthetic-test','available')",bytes(UUID.randomUUID()),bytes(org),bytes(capture),bytes(asset),"a".repeat(64));
        return new UUID[]{pen,session,asset};
    }
    private static byte[] bytes(UUID id) { return ByteBuffer.allocate(16).putLong(id.getMostSignificantBits()).putLong(id.getLeastSignificantBits()).array(); }
}
