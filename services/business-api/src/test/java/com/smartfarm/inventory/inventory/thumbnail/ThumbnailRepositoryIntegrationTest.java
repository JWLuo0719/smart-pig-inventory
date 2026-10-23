package com.smartfarm.inventory.inventory.thumbnail;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

import com.smartfarm.inventory.inventory.application.InventoryException;
import com.smartfarm.inventory.inventory.infrastructure.SecurityReviewActor;
import java.nio.ByteBuffer;
import java.util.UUID;
import org.flywaydb.core.Flyway;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.testcontainers.containers.MySQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

/** Real schema/CAS coverage; object transport remains synthetic and no production project is touched. */
@Testcontainers(disabledWithoutDocker = true)
class ThumbnailRepositoryIntegrationTest {
    @Container
    static final MySQLContainer<?> MYSQL = new MySQLContainer<>("mysql:8.4")
            .withDatabaseName("pig_inventory").withUsername("pig_inventory").withPassword("synthetic-test-only-password");

    @Test
    void realJdbcGenerationPointerCacheMissOrganizationAndDeletionKeepOriginalImmutable() throws Exception {
        Flyway.configure().dataSource(MYSQL.getJdbcUrl(), MYSQL.getUsername(), MYSQL.getPassword()).load().migrate();
        JdbcTemplate jdbc = new JdbcTemplate(new DriverManagerDataSource(MYSQL.getJdbcUrl(), MYSQL.getUsername(), MYSQL.getPassword()));
        UUID organization = UUID.randomUUID(), building = UUID.randomUUID(), pen = UUID.randomUUID();
        UUID session = UUID.randomUUID(), pack = UUID.randomUUID(), set = UUID.randomUUID(), asset = UUID.randomUUID();
        byte[] original = ThumbnailCodecTest.image("png", 600, 300);
        String hash = "b".repeat(64);
        jdbc.update("INSERT INTO farm_organization(id,code,name) VALUES (?,'thumb-org','Synthetic thumbnail farm')", bytes(organization));
        jdbc.update("INSERT INTO building(id,organization_id,code,name) VALUES (?,?,'b1','Building')", bytes(building), bytes(organization));
        jdbc.update("INSERT INTO pen(id,building_id,code,name) VALUES (?,?,'p1','Pen')", bytes(pen), bytes(building));
        jdbc.update("INSERT INTO inventory_session(id,pen_id,business_date,status,created_by) VALUES (?,?,'2026-10-23','review_required','synthetic')",
                bytes(session), bytes(pen));
        jdbc.update("""
                INSERT INTO upload_package(id,organization_id,pen_id,client_package_id,business_date,capture_kind,idempotency_key,state)
                VALUES (?,?,?,?,'2026-10-23','single','synthetic-thumbnail','committed')
                """, bytes(pack), bytes(organization), bytes(pen), bytes(UUID.randomUUID()));
        jdbc.update("INSERT INTO upload_blob(asset_id,package_id,sha256,byte_size,content_type,storage_key) VALUES (?,?,?,?, 'image/png','original')",
                bytes(asset), bytes(pack), hash, original.length);
        jdbc.update("INSERT INTO capture_set(id,session_id,upload_package_id,client_capture_id,kind) VALUES (?,?,?,?,'single')",
                bytes(set), bytes(session), bytes(pack), bytes(UUID.randomUUID()));
        jdbc.update("""
                INSERT INTO media_asset(id,organization_id,capture_set_id,asset_id,view_position,original_name,
                    content_type,byte_size,sha256,storage_key,state)
                VALUES (?,?,?,?,'single','synthetic.png','image/png',?,?,'original','submitted')
                """, bytes(UUID.randomUUID()), bytes(organization), bytes(set), bytes(asset), original.length, hash);
        var repository = new JdbcThumbnailRepository(jdbc);
        var storage = new ThumbnailServiceTest.MemoryStorage();
        storage.objects.put("original", original);
        var actor = mock(SecurityReviewActor.class);
        when(actor.activeOrganizationId()).thenReturn(organization);
        var service = new ThumbnailService(repository, storage, new ThumbnailCodec(), actor);
        byte[] thumbnail = service.thumbnail(asset);
        String key = repository.find(organization, asset).orElseThrow().thumbnailKey();
        assertNotNull(key);
        assertArrayEquals(thumbnail, service.thumbnail(asset));
        storage.objects.remove(key);
        assertTrue(new ThumbnailCodec().validCached(service.thumbnail(asset)));
        assertTrue(repository.find(UUID.randomUUID(), asset).isEmpty());
        when(actor.activeOrganizationId()).thenReturn(UUID.randomUUID());
        assertEquals(404, assertThrows(InventoryException.class, () -> service.thumbnail(asset)).status());
        when(actor.activeOrganizationId()).thenReturn(organization);
        jdbc.update("UPDATE media_asset SET state='deleted',deleted_at=CURRENT_TIMESTAMP(6) WHERE asset_id=?", bytes(asset));
        assertTrue(repository.find(organization, asset).isEmpty());
        assertFalse(repository.attach(new JdbcThumbnailRepository.Source(organization, asset, "image/png",
                original.length, hash, "original", key), key));
        assertEquals(404, assertThrows(InventoryException.class, () -> service.thumbnail(asset)).status());
        assertArrayEquals(original, storage.objects.get("original"));
        assertEquals(hash, jdbc.queryForObject("SELECT sha256 FROM media_asset WHERE asset_id=?", String.class, bytes(asset)));
        assertEquals(0, jdbc.queryForObject("SELECT COUNT(*) FROM audit_event", Integer.class));
    }

    private static byte[] bytes(UUID id) {
        return ByteBuffer.allocate(16).putLong(id.getMostSignificantBits()).putLong(id.getLeastSignificantBits()).array();
    }
}
