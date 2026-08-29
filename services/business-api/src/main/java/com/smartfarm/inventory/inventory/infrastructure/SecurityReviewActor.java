package com.smartfarm.inventory.inventory.infrastructure;

import com.smartfarm.inventory.inventory.application.InventoryException;
import java.nio.ByteBuffer;
import java.util.List;
import java.util.UUID;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.springframework.stereotype.Component;

/** Resolves authorization from the signed active organization, never from a request field. */
@Component
public class SecurityReviewActor {
    private final boolean securityEnabled;
    private final JdbcTemplate jdbc;

    public SecurityReviewActor(@Value("${app.security.enabled:true}") boolean securityEnabled, JdbcTemplate jdbc) {
        this.securityEnabled = securityEnabled;
        this.jdbc = jdbc;
    }

    public String subjectId() {
        if (!securityEnabled) {
            return "local-dev";
        }
        Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
        if (authentication == null || authentication.getName() == null || authentication.getName().isBlank()) {
            throw InventoryException.notFound();
        }
        return authentication.getName();
    }

    public UUID activeOrganizationId() {
        if (!securityEnabled) {
            List<UUID> organizations = jdbc.query("SELECT id FROM farm_organization ORDER BY created_at LIMIT 1",
                    (resultSet, rowNumber) -> fromBytes(resultSet.getBytes("id")));
            return organizations.stream().findFirst().orElseThrow(InventoryException::notFound);
        }
        Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
        if (!(authentication instanceof JwtAuthenticationToken jwt)) {
            throw InventoryException.notFound();
        }
        String organizationId = jwt.getToken().getClaimAsString("active_organization_id");
        if (organizationId == null) {
            throw InventoryException.notFound();
        }
        try {
            return UUID.fromString(organizationId);
        } catch (IllegalArgumentException exception) {
            throw InventoryException.notFound();
        }
    }

    public void assertCanView(UUID organizationId) {
        assertRole(organizationId, List.of("OPERATOR", "REVIEWER", "FARM_ADMIN", "SYSTEM_ADMIN"));
    }

    public void assertCanConfirm(UUID organizationId) {
        assertRole(organizationId, List.of("REVIEWER", "FARM_ADMIN", "SYSTEM_ADMIN"));
    }

    public void assertCanOverrideDelete(UUID organizationId) {
        assertRole(organizationId, List.of("FARM_ADMIN", "SYSTEM_ADMIN"));
    }

    public void assertCanAudit(UUID organizationId) {
        assertRole(organizationId, List.of("FARM_ADMIN", "SYSTEM_ADMIN"));
    }

    private void assertRole(UUID organizationId, List<String> allowedRoles) {
        if (!securityEnabled) {
            return;
        }
        Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
        if (!(authentication instanceof JwtAuthenticationToken jwt)
                || !organizationId.toString().equals(jwt.getToken().getClaimAsString("active_organization_id"))) {
            throw InventoryException.notFound();
        }
        Integer allowed = jdbc.queryForObject("""
                SELECT COUNT(*) FROM organization_membership
                WHERE organization_id = ? AND subject_id = ? AND enabled = TRUE
                  AND role_key IN (?, ?, ?, ?)
                """, Integer.class, bytes(organizationId), jwt.getName(),
                allowedRoles.getFirst(), allowedRoles.size() > 1 ? allowedRoles.get(1) : "__none__",
                allowedRoles.size() > 2 ? allowedRoles.get(2) : "__none__",
                allowedRoles.size() > 3 ? allowedRoles.get(3) : "__none__");
        if (allowed == null || allowed == 0) {
            throw InventoryException.notFound();
        }
    }

    private static byte[] bytes(UUID uuid) {
        return ByteBuffer.allocate(16).putLong(uuid.getMostSignificantBits()).putLong(uuid.getLeastSignificantBits()).array();
    }

    private static UUID fromBytes(byte[] value) {
        return new UUID(ByteBuffer.wrap(value).getLong(), ByteBuffer.wrap(value).getLong(8));
    }
}
