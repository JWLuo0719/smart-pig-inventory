package com.smartfarm.inventory.identity.infrastructure;

import java.nio.ByteBuffer;
import java.util.List;
import java.util.UUID;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

/**
 * Creates only locally-generated identities and master data for the isolated P0 Compose project.
 * It is disabled by default and deliberately has no production configuration path.
 */
@Component
@ConditionalOnProperty(name = "app.security.e2e-fixtures-enabled", havingValue = "true")
public class SyntheticE2eFixtureInitializer implements ApplicationRunner {
    private final JdbcTemplate jdbc;
    private final PasswordEncoder passwordEncoder;
    private final String password;
    private final String primaryOrganizationCode;

    public SyntheticE2eFixtureInitializer(JdbcTemplate jdbc, PasswordEncoder passwordEncoder,
            @Value("${app.security.e2e-fixture-password:}") String password,
            @Value("${app.security.bootstrap-organization-code:DEV-E2E}") String primaryOrganizationCode) {
        this.jdbc = jdbc;
        this.passwordEncoder = passwordEncoder;
        this.password = password;
        this.primaryOrganizationCode = primaryOrganizationCode;
    }

    @Override
    @Transactional
    public void run(ApplicationArguments args) {
        if (password.isBlank()) {
            throw new IllegalStateException("Synthetic E2E fixtures require a locally generated fixture password");
        }
        UUID primary = organization(primaryOrganizationCode, "Local E2E Synthetic Farm");
        UUID secondary = organization("E2E-SECOND", "Local E2E Synthetic Farm Two");
        ensureBuildingAndPen(primary, "E2E-B01", "E2E Synthetic Building", "E2E-P01", "E2E Synthetic Pen One");
        ensureBuildingAndPen(primary, "E2E-B01", "E2E Synthetic Building", "E2E-P02", "E2E Synthetic Pen Two");
        ensureBuildingAndPen(secondary, "E2E2-B01", "E2E Synthetic Building Two", "E2E2-P01", "E2E Synthetic Pen Two");
        ensureUser(primary, "e2e-operator", "E2E Operator", "OPERATOR");
        ensureUser(primary, "e2e-reviewer", "E2E Reviewer", "REVIEWER");
        ensureUser(primary, "e2e-farm-admin", "E2E Farm Administrator", "FARM_ADMIN");
        ensureUser(secondary, "e2e-second-operator", "E2E Second Organization Operator", "OPERATOR");
    }

    private UUID organization(String code, String name) {
        List<UUID> existing = jdbc.query("SELECT id FROM farm_organization WHERE code = ?", (rs, row) -> uuid(rs.getBytes(1)), code);
        if (!existing.isEmpty()) return existing.getFirst();
        UUID id = UUID.randomUUID();
        jdbc.update("INSERT INTO farm_organization (id, code, name) VALUES (?, ?, ?)", bytes(id), code, name);
        return id;
    }

    private void ensureBuildingAndPen(UUID organizationId, String buildingCode, String buildingName, String penCode, String penName) {
        List<UUID> buildings = jdbc.query("SELECT id FROM building WHERE organization_id = ? AND code = ?",
                (rs, row) -> uuid(rs.getBytes(1)), bytes(organizationId), buildingCode);
        UUID buildingId = buildings.isEmpty() ? UUID.randomUUID() : buildings.getFirst();
        if (buildings.isEmpty()) {
            jdbc.update("INSERT INTO building (id, organization_id, code, name, sync_version) VALUES (?, ?, ?, ?, 1)",
                    bytes(buildingId), bytes(organizationId), buildingCode, buildingName);
        }
        Integer pens = jdbc.queryForObject("SELECT COUNT(*) FROM pen WHERE building_id = ? AND code = ?", Integer.class,
                bytes(buildingId), penCode);
        if (pens == null || pens == 0) {
            jdbc.update("INSERT INTO pen (id, building_id, code, name, sync_version) VALUES (?, ?, ?, ?, 2)",
                    bytes(UUID.randomUUID()), bytes(buildingId), penCode, penName);
        }
    }

    private void ensureUser(UUID organizationId, String username, String displayName, String role) {
        List<String> subjects = jdbc.query("SELECT subject_id FROM app_user WHERE username = ?", (rs, row) -> rs.getString(1), username);
        String subjectId;
        if (subjects.isEmpty()) {
            subjectId = "local:" + username;
            jdbc.update("INSERT INTO app_user (id, subject_id, username, display_name, password_hash) VALUES (?, ?, ?, ?, ?)",
                    bytes(UUID.randomUUID()), subjectId, username, displayName, passwordEncoder.encode(password));
        } else {
            subjectId = subjects.getFirst();
        }
        Integer memberships = jdbc.queryForObject("SELECT COUNT(*) FROM organization_membership WHERE organization_id = ? AND subject_id = ?",
                Integer.class, bytes(organizationId), subjectId);
        if (memberships == null || memberships == 0) {
            jdbc.update("INSERT INTO organization_membership (id, organization_id, subject_id, role_key) VALUES (?, ?, ?, ?)",
                    bytes(UUID.randomUUID()), bytes(organizationId), subjectId, role);
        }
    }

    private static byte[] bytes(UUID value) {
        return ByteBuffer.allocate(16).putLong(value.getMostSignificantBits()).putLong(value.getLeastSignificantBits()).array();
    }

    private static UUID uuid(byte[] value) {
        ByteBuffer buffer = ByteBuffer.wrap(value);
        return new UUID(buffer.getLong(), buffer.getLong());
    }
}
