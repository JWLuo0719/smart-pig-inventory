package com.smartfarm.inventory.capture.infrastructure;

import com.smartfarm.inventory.capture.application.UploadActor;
import com.smartfarm.inventory.capture.application.UploadException;
import java.util.UUID;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.springframework.stereotype.Component;

@Component
public class SecurityUploadActor implements UploadActor {
    private final boolean securityEnabled;
    private final JdbcTemplate jdbc;

    public SecurityUploadActor(@Value("${app.security.enabled:true}") boolean securityEnabled, JdbcTemplate jdbc) {
        this.securityEnabled = securityEnabled;
        this.jdbc = jdbc;
    }

    @Override
    public void assertCanAccess(UUID organizationId) {
        if (!securityEnabled) {
            return;
        }
        Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
        if (!(authentication instanceof JwtAuthenticationToken jwt)) {
            throw UploadException.forbidden("An authenticated organization member is required");
        }
        String activeOrganization = jwt.getToken().getClaimAsString("active_organization_id");
        if (activeOrganization == null || !organizationId.toString().equals(activeOrganization)) {
            throw UploadException.notFound();
        }
        Integer memberships = jdbc.queryForObject("""
                SELECT COUNT(*) FROM organization_membership
                WHERE organization_id = ? AND subject_id = ? AND enabled = TRUE
                  AND role_key IN ('OPERATOR', 'FARM_ADMIN', 'SYSTEM_ADMIN')
                """, Integer.class, bytes(organizationId), jwt.getName());
        if (memberships == null || memberships == 0) {
            throw UploadException.notFound();
        }
    }

    @Override
    public String subjectId() {
        if (!securityEnabled) {
            return "local-dev";
        }
        Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
        if (authentication == null || authentication.getName() == null || authentication.getName().isBlank()) {
            throw UploadException.forbidden("An authenticated subject is required");
        }
        return authentication.getName();
    }

    private static byte[] bytes(UUID uuid) {
        return java.nio.ByteBuffer.allocate(16).putLong(uuid.getMostSignificantBits()).putLong(uuid.getLeastSignificantBits()).array();
    }
}
