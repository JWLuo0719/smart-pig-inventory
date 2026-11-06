package com.smartfarm.inventory.inventory.infrastructure;

import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.assertj.core.api.Assertions.assertThat;

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
@org.springframework.transaction.annotation.Transactional
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
    @Autowired private com.smartfarm.inventory.inventory.application.InventoryReviewService reviews;

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
        membership(primaryOrganization, "e2e-competition-viewer", "COMPETITION_VIEWER");
        membership(secondOrganization, "e2e-second-operator", "OPERATOR");
    }

    @AfterEach
    void clearAuthentication() {
        SecurityContextHolder.clearContext();
    }

    @Test
    void enforcesOperatorReviewerFarmAdminAndCrossOrganizationBoundaries() {
        UUID building = UUID.randomUUID(), pen = UUID.randomUUID(), session = UUID.randomUUID();
        jdbc.update("INSERT INTO building (id,organization_id,code,name) VALUES (?,?,'BV','Synthetic versions')", bytes(building), bytes(primaryOrganization));
        jdbc.update("INSERT INTO pen (id,building_id,code,name) VALUES (?,?,'PV','Synthetic versions')", bytes(pen), bytes(building));
        jdbc.update("""
                INSERT INTO inventory_session
                (id,pen_id,business_date,status,candidate_count,confirmed_count,version,created_by,
                 confirmed_by,confirmed_at,confirmation_idempotency_key)
                VALUES (?,?,'2026-10-20','confirmed',17,17,1,'synthetic','synthetic',CURRENT_TIMESTAMP(6),?)
                """, bytes(session), bytes(pen), UUID.randomUUID().toString());
        authenticate("e2e-operator", primaryOrganization, "OPERATOR");
        assertThatThrownBy(() -> reviews.versions(session, null, 20)).isInstanceOf(InventoryException.class);
        assertThatCode(() -> actor.assertCanView(primaryOrganization)).doesNotThrowAnyException();
        assertThatThrownBy(() -> actor.assertCanConfirm(primaryOrganization)).isInstanceOf(InventoryException.class)
                .hasMessageContaining("not available");
        assertThatThrownBy(() -> actor.assertCanOverrideDelete(primaryOrganization)).isInstanceOf(InventoryException.class);
        assertThatThrownBy(() -> actor.assertCanManageInference(primaryOrganization)).isInstanceOf(InventoryException.class);
        assertThatThrownBy(() -> actor.assertCanCorrect(primaryOrganization)).isInstanceOf(InventoryException.class);

        authenticate("e2e-reviewer", primaryOrganization, "REVIEWER");
        assertThatThrownBy(() -> reviews.versions(session, null, 20)).isInstanceOf(InventoryException.class);
        assertThatCode(() -> actor.assertCanConfirm(primaryOrganization)).doesNotThrowAnyException();
        assertThatThrownBy(() -> actor.assertCanOverrideDelete(primaryOrganization)).isInstanceOf(InventoryException.class);
        assertThatThrownBy(() -> actor.assertCanManageInference(primaryOrganization)).isInstanceOf(InventoryException.class);
        assertThatThrownBy(() -> actor.assertCanCorrect(primaryOrganization)).isInstanceOf(InventoryException.class);

        authenticate("e2e-farm-admin", primaryOrganization, "FARM_ADMIN");
        assertThat(reviews.versions(session, null, 20).currentSessionId()).isEqualTo(session);
        assertThat(reviews.versions(session, null, 20).items()).hasSize(1);
        assertThatCode(() -> actor.assertCanConfirm(primaryOrganization)).doesNotThrowAnyException();
        assertThatCode(() -> actor.assertCanOverrideDelete(primaryOrganization)).doesNotThrowAnyException();
        assertThatCode(() -> actor.assertCanAudit(primaryOrganization)).doesNotThrowAnyException();
        assertThatCode(() -> actor.assertCanManageInference(primaryOrganization)).doesNotThrowAnyException();
        assertThatCode(() -> actor.assertCanCorrect(primaryOrganization)).doesNotThrowAnyException();

        authenticate("e2e-second-operator", secondOrganization, "OPERATOR");
        assertThatThrownBy(() -> reviews.versions(session, null, 20)).isInstanceOf(InventoryException.class)
                .hasMessageContaining("not available");
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

    @Test
    void competitionViewerCanReadButCannotUseAnyWritePrivilege() {
        authenticate("e2e-competition-viewer", primaryOrganization, "COMPETITION_VIEWER");
        assertThatCode(() -> actor.assertCanView(primaryOrganization)).doesNotThrowAnyException();
        assertThatThrownBy(() -> actor.assertCanView(secondOrganization)).isInstanceOf(InventoryException.class);
        assertThatThrownBy(() -> actor.assertCanConfirm(primaryOrganization)).isInstanceOf(InventoryException.class);
        assertThatThrownBy(() -> actor.assertCanDeleteEvidence(primaryOrganization)).isInstanceOf(InventoryException.class);
        assertThatThrownBy(() -> actor.assertCanOverrideDelete(primaryOrganization)).isInstanceOf(InventoryException.class);
        assertThatThrownBy(() -> actor.assertCanCorrect(primaryOrganization)).isInstanceOf(InventoryException.class);
        assertThatThrownBy(() -> actor.assertCanManageInference(primaryOrganization)).isInstanceOf(InventoryException.class);
        assertThatThrownBy(() -> actor.assertCanManageMasterData(primaryOrganization)).isInstanceOf(InventoryException.class);
        var uploads = new com.smartfarm.inventory.capture.infrastructure.SecurityUploadActor(true, jdbc);
        assertThatThrownBy(() -> uploads.assertCanAccess(primaryOrganization))
                .isInstanceOf(com.smartfarm.inventory.capture.application.UploadException.class);
        jdbc.update("UPDATE organization_membership SET access_expires_at=DATE_SUB(CURRENT_TIMESTAMP(6), INTERVAL 1 SECOND) WHERE subject_id='e2e-competition-viewer'");
        assertThatThrownBy(() -> actor.assertCanView(primaryOrganization)).isInstanceOf(InventoryException.class);
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
