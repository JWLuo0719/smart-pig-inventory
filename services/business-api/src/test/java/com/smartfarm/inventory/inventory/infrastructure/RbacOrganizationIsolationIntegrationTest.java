package com.smartfarm.inventory.inventory.infrastructure;

import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.smartfarm.inventory.BusinessApiApplication;
import com.smartfarm.inventory.inventory.application.InventoryException;
import java.nio.ByteBuffer;
import java.util.List;
import java.util.UUID;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.testcontainers.containers.MySQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

/** Exercises real MySQL membership checks with signed, organization-bound JWTs. */
@SpringBootTest(classes = BusinessApiApplication.class, properties = {
        "app.security.enabled=true",
        "app.security.jwt-signing-secret=MDEyMzQ1Njc4OWFiY2RlZjAxMjM0NTY3ODlhYmNkZWY=",
        "app.object-storage.secret-key=test-secret",
        "app.inference.dispatcher.enabled=false"})
@Testcontainers(disabledWithoutDocker = true)
class RbacOrganizationIsolationIntegrationTest {
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
    @Autowired private JwtDecoder jwtDecoder;
    @Autowired private com.smartfarm.inventory.identity.infrastructure.JwtTokenService tokens;
    @Autowired private SecurityReviewActor actor;

    private UUID primaryOrganization;
    private UUID secondOrganization;

    @BeforeEach
    void seed() {
        jdbc.update("DELETE FROM organization_membership");
        jdbc.update("DELETE FROM farm_organization");
        primaryOrganization = organization("E2E-PRIMARY");
        secondOrganization = organization("E2E-SECOND");
        membership(primaryOrganization, "e2e-operator", "OPERATOR");
        membership(primaryOrganization, "e2e-reviewer", "REVIEWER");
        membership(primaryOrganization, "e2e-farm-admin", "FARM_ADMIN");
        membership(secondOrganization, "e2e-second-operator", "OPERATOR");
    }

    @AfterEach
    void clearAuthentication() {
        SecurityContextHolder.clearContext();
    }

    @Test
    void enforcesOperatorReviewerFarmAdminAndCrossOrganizationBoundaries() {
        authenticate("e2e-operator", primaryOrganization, "OPERATOR");
        assertThatCode(() -> actor.assertCanView(primaryOrganization)).doesNotThrowAnyException();
        assertThatThrownBy(() -> actor.assertCanConfirm(primaryOrganization)).isInstanceOf(InventoryException.class)
                .hasMessageContaining("not available");
        assertThatThrownBy(() -> actor.assertCanOverrideDelete(primaryOrganization)).isInstanceOf(InventoryException.class);

        authenticate("e2e-reviewer", primaryOrganization, "REVIEWER");
        assertThatCode(() -> actor.assertCanConfirm(primaryOrganization)).doesNotThrowAnyException();
        assertThatThrownBy(() -> actor.assertCanOverrideDelete(primaryOrganization)).isInstanceOf(InventoryException.class);

        authenticate("e2e-farm-admin", primaryOrganization, "FARM_ADMIN");
        assertThatCode(() -> actor.assertCanConfirm(primaryOrganization)).doesNotThrowAnyException();
        assertThatCode(() -> actor.assertCanOverrideDelete(primaryOrganization)).doesNotThrowAnyException();
        assertThatCode(() -> actor.assertCanAudit(primaryOrganization)).doesNotThrowAnyException();

        authenticate("e2e-second-operator", secondOrganization, "OPERATOR");
        assertThatCode(() -> actor.assertCanView(secondOrganization)).doesNotThrowAnyException();
        assertThatThrownBy(() -> actor.assertCanView(primaryOrganization)).isInstanceOf(InventoryException.class)
                .hasMessageContaining("not available");
    }

    private void authenticate(String subject, UUID organizationId, String role) {
        String value = tokens.issue(subject, organizationId,
                List.of(new com.smartfarm.inventory.identity.domain.IdentityModels.Membership(organizationId, "E2E", "Synthetic", role))).value();
        Jwt jwt = jwtDecoder.decode(value);
        SecurityContextHolder.getContext().setAuthentication(new JwtAuthenticationToken(jwt));
    }

    private UUID organization(String code) {
        UUID id = UUID.randomUUID();
        jdbc.update("INSERT INTO farm_organization (id, code, name) VALUES (?, ?, ?)", bytes(id), code, code);
        return id;
    }

    private void membership(UUID organizationId, String subject, String role) {
        jdbc.update("INSERT INTO organization_membership (id, organization_id, subject_id, role_key) VALUES (?, ?, ?, ?)",
                bytes(UUID.randomUUID()), bytes(organizationId), subject, role);
    }

    private static byte[] bytes(UUID id) {
        return ByteBuffer.allocate(16).putLong(id.getMostSignificantBits()).putLong(id.getLeastSignificantBits()).array();
    }
}
