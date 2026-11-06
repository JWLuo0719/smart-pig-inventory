package com.smartfarm.inventory.identity.infrastructure;

import java.nio.ByteBuffer;
import java.sql.Timestamp;
import java.time.Instant;
import java.util.UUID;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

/** Explicit opt-in provisioning for a dedicated, expiring, read-only competition identity. */
@Component
@ConditionalOnProperty(name = "app.assistant.viewer-provision-enabled", havingValue = "true")
public class CompetitionViewerInitializer implements ApplicationRunner {
    private final JdbcTemplate jdbc; private final PasswordEncoder passwords;
    private final String username, password, organizationCode; private final Instant expires;
    public CompetitionViewerInitializer(JdbcTemplate jdbc, PasswordEncoder passwords,
            @Value("${app.security.enabled:true}") boolean securityEnabled,
            @Value("${app.assistant.viewer-username:}") String username,
            @Value("${app.assistant.viewer-password:}") String password,
            @Value("${app.assistant.viewer-organization-code:}") String organizationCode,
            @Value("${app.assistant.viewer-expires-at:}") String expiresAt) {
        this.jdbc = jdbc; this.passwords = passwords; this.username = username; this.password = password; this.organizationCode = organizationCode;
        try { expires = Instant.parse(expiresAt); }
        catch (RuntimeException exception) { throw new IllegalArgumentException("Competition viewer requires an explicit expiration"); }
        if (!securityEnabled || username.isBlank() || username.length() > 128 || password.length() < 16 || password.length() > 256
                || organizationCode.isBlank() || !expires.isAfter(Instant.now())
                || expires.isAfter(Instant.now().plusSeconds(180L * 86400))) {
            throw new IllegalArgumentException("Competition viewer provisioning requires secure explicit settings");
        }
    }
    @Override @Transactional public void run(ApplicationArguments arguments) {
        var organizations = jdbc.query("SELECT id FROM farm_organization WHERE code=? AND enabled=TRUE",
                (rs, n) -> uuid(rs.getBytes("id")), organizationCode);
        if (organizations.size() != 1) throw new IllegalStateException("Competition organization must already exist");
        UUID org = organizations.getFirst();
        var users = jdbc.query("SELECT subject_id,password_hash,enabled FROM app_user WHERE username=?",
                (rs, n) -> new ExistingUser(rs.getString("subject_id"), rs.getString("password_hash"), rs.getBoolean("enabled")), username);
        if (!users.isEmpty()) {
            var user = users.getFirst();
            var memberships = jdbc.query("SELECT organization_id,role_key,enabled,access_expires_at FROM organization_membership WHERE subject_id=?",
                    (rs, n) -> new Membership(uuid(rs.getBytes("organization_id")), rs.getString("role_key"), rs.getBoolean("enabled"), rs.getTimestamp("access_expires_at")), user.subject());
            if (!user.enabled() || !passwords.matches(password, user.password()) || memberships.size() != 1
                    || !memberships.getFirst().organization().equals(org) || !"COMPETITION_VIEWER".equals(memberships.getFirst().role())
                    || !memberships.getFirst().enabled() || memberships.getFirst().expires() == null
                    || !memberships.getFirst().expires().toInstant().equals(expires)) {
                throw new IllegalStateException("Existing username cannot be repurposed or modified by competition provisioning");
            }
            return;
        }
        String subject = "competition:" + UUID.randomUUID();
        jdbc.update("INSERT INTO app_user (id,subject_id,username,display_name,password_hash) VALUES (?,?,?,?,?)",
                bytes(UUID.randomUUID()), subject, username, "作品体验账号", passwords.encode(password));
        jdbc.update("INSERT INTO organization_membership (id,organization_id,subject_id,role_key,access_expires_at) VALUES (?,?,?,?,?)",
                bytes(UUID.randomUUID()), bytes(org), subject, "COMPETITION_VIEWER", Timestamp.from(expires));
    }
    private static byte[] bytes(UUID id) { return ByteBuffer.allocate(16).putLong(id.getMostSignificantBits()).putLong(id.getLeastSignificantBits()).array(); }
    private static UUID uuid(byte[] bytes) { return new UUID(ByteBuffer.wrap(bytes).getLong(), ByteBuffer.wrap(bytes).getLong(8)); }
    private record ExistingUser(String subject, String password, boolean enabled) {}
    private record Membership(UUID organization, String role, boolean enabled, Timestamp expires) {}
}
