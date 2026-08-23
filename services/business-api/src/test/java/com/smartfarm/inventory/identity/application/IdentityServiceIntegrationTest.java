package com.smartfarm.inventory.identity.application;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;

import com.smartfarm.inventory.BusinessApiApplication;
import com.smartfarm.inventory.identity.domain.IdentityModels.CurrentUser;
import com.smartfarm.inventory.identity.domain.IdentityModels.TokenPair;
import com.smartfarm.inventory.identity.infrastructure.BootstrapAdminInitializer;
import java.nio.ByteBuffer;
import java.time.Instant;
import java.util.Base64;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.jwt.JwtDecoder;
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
class IdentityServiceIntegrationTest {
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
    private IdentityService service;

    @Autowired
    private JdbcTemplate jdbc;

    @Autowired
    private PasswordEncoder passwordEncoder;

    @Autowired
    private JwtDecoder jwtDecoder;

    private UUID organizationId;
    private String subjectId;

    @BeforeEach
    void seedUser() {
        jdbc.update("DELETE FROM auth_refresh_session");
        jdbc.update("DELETE FROM organization_membership");
        jdbc.update("DELETE FROM app_user");
        jdbc.update("DELETE FROM farm_organization");
        organizationId = UUID.randomUUID();
        UUID userId = UUID.randomUUID();
        subjectId = "local:test-subject";
        jdbc.update("INSERT INTO farm_organization (id, code, name) VALUES (?, 'test-org', 'Test organization')",
                bytes(organizationId));
        jdbc.update("""
                INSERT INTO app_user (id, subject_id, username, display_name, password_hash)
                VALUES (?, ?, 'operator', 'Test operator', ?)
                """, bytes(userId), subjectId, passwordEncoder.encode("correct-horse-battery"));
        jdbc.update("""
                INSERT INTO organization_membership (id, organization_id, subject_id, role_key)
                VALUES (?, ?, ?, 'OPERATOR')
                """, bytes(UUID.randomUUID()), bytes(organizationId), subjectId);
    }

    @Test
    void loginStoresOnlyRefreshHashAndIssuesOrganizationBoundJwt() {
        TokenPair pair = service.login("operator", "correct-horse-battery");

        assertEquals("Bearer", pair.tokenType());
        assertNotEquals(pair.refreshToken(), jdbc.queryForObject("SELECT token_hash FROM auth_refresh_session", String.class));
        Jwt jwt = jwtDecoder.decode(pair.accessToken());
        assertEquals(subjectId, jwt.getSubject());
        assertEquals(organizationId.toString(), jwt.getClaimAsString("active_organization_id"));
        assertEquals(Instant.now().isBefore(pair.accessTokenExpiresAt()), true);

        CurrentUser currentUser = service.currentUser(subjectId, organizationId);
        assertEquals("Test operator", currentUser.displayName());
        assertEquals("OPERATOR", currentUser.memberships().getFirst().roles().getFirst());
    }

    @Test
    void bootstrapCreatesOnlyTheFirstConfiguredAdministrator() throws Exception {
        BootstrapAdminInitializer initial = new BootstrapAdminInitializer(
                jdbc, passwordEncoder, "bootstrap-admin", "first-password", "Bootstrap Admin", "bootstrap-org", "Bootstrap Organization");
        initial.run(null);
        String originalHash = jdbc.queryForObject("SELECT password_hash FROM app_user WHERE username = 'bootstrap-admin'", String.class);
        assertEquals(true, passwordEncoder.matches("first-password", originalHash));

        new BootstrapAdminInitializer(
                jdbc, passwordEncoder, "bootstrap-admin", "changed-password", "Changed", "bootstrap-org", "Changed Organization").run(null);
        assertEquals(1, jdbc.queryForObject("SELECT COUNT(*) FROM app_user WHERE username = 'bootstrap-admin'", Integer.class));
        assertEquals(true, passwordEncoder.matches("first-password",
                jdbc.queryForObject("SELECT password_hash FROM app_user WHERE username = 'bootstrap-admin'", String.class)));
    }

    @Test
    void refreshRotatesTokenAndLogoutRevokesTheCurrentSession() {
        TokenPair login = service.login("operator", "correct-horse-battery");
        TokenPair refreshed = service.refresh(login.refreshToken());

        assertNotEquals(login.refreshToken(), refreshed.refreshToken());
        assertThrows(IdentityException.class, () -> service.refresh(login.refreshToken()));
        service.logout(subjectId, refreshed.refreshToken());
        assertThrows(IdentityException.class, () -> service.refresh(refreshed.refreshToken()));
    }

    private static byte[] bytes(UUID uuid) {
        return ByteBuffer.allocate(16).putLong(uuid.getMostSignificantBits()).putLong(uuid.getLeastSignificantBits()).array();
    }
}
