package com.smartfarm.inventory.identity.infrastructure;

import java.nio.ByteBuffer;
import java.util.UUID;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

@Component
@ConditionalOnProperty(name = "app.security.enabled", havingValue = "true", matchIfMissing = true)
public class BootstrapAdminInitializer implements ApplicationRunner {
    private final JdbcTemplate jdbc;
    private final PasswordEncoder passwordEncoder;
    private final String username;
    private final String password;
    private final String displayName;
    private final String organizationCode;
    private final String organizationName;

    public BootstrapAdminInitializer(
            JdbcTemplate jdbc,
            PasswordEncoder passwordEncoder,
            @Value("${app.security.bootstrap-admin-username:}") String username,
            @Value("${app.security.bootstrap-admin-password:}") String password,
            @Value("${app.security.bootstrap-admin-display-name:}") String displayName,
            @Value("${app.security.bootstrap-organization-code:}") String organizationCode,
            @Value("${app.security.bootstrap-organization-name:}") String organizationName) {
        this.jdbc = jdbc;
        this.passwordEncoder = passwordEncoder;
        this.username = username;
        this.password = password;
        this.displayName = displayName;
        this.organizationCode = organizationCode;
        this.organizationName = organizationName;
    }

    @Override
    @Transactional
    public void run(ApplicationArguments args) {
        if (username.isBlank() && password.isBlank() && organizationCode.isBlank() && organizationName.isBlank()) {
            return;
        }
        if (username.isBlank() || password.isBlank() || organizationCode.isBlank() || organizationName.isBlank()) {
            throw new IllegalStateException("Bootstrap admin requires username, password, organization code and organization name");
        }
        Integer existingUser = jdbc.queryForObject("SELECT COUNT(*) FROM app_user WHERE username = ?", Integer.class, username);
        if (existingUser != null && existingUser > 0) {
            return;
        }
        UUID organizationId = findOrCreateOrganization();
        UUID userId = UUID.randomUUID();
        String subjectId = "local:" + UUID.randomUUID();
        jdbc.update("""
                INSERT INTO app_user (id, subject_id, username, display_name, password_hash)
                VALUES (?, ?, ?, ?, ?)
                """, bytes(userId), subjectId, username,
                displayName.isBlank() ? username : displayName, passwordEncoder.encode(password));
        jdbc.update("""
                INSERT INTO organization_membership (id, organization_id, subject_id, role_key)
                VALUES (?, ?, ?, 'SYSTEM_ADMIN')
                """, bytes(UUID.randomUUID()), bytes(organizationId), subjectId);
    }

    private UUID findOrCreateOrganization() {
        return jdbc.query("SELECT id FROM farm_organization WHERE code = ?", (resultSet, rowNumber) -> readUuid(resultSet.getBytes(1)), organizationCode)
                .stream().findFirst().orElseGet(() -> {
                    UUID organizationId = UUID.randomUUID();
                    jdbc.update("INSERT INTO farm_organization (id, code, name) VALUES (?, ?, ?)",
                            bytes(organizationId), organizationCode, organizationName);
                    return organizationId;
                });
    }

    private static byte[] bytes(UUID value) {
        return ByteBuffer.allocate(16).putLong(value.getMostSignificantBits()).putLong(value.getLeastSignificantBits()).array();
    }

    private static UUID readUuid(byte[] value) {
        ByteBuffer buffer = ByteBuffer.wrap(value);
        return new UUID(buffer.getLong(), buffer.getLong());
    }
}
