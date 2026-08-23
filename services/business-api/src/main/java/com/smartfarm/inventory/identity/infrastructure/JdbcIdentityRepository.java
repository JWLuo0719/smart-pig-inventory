package com.smartfarm.inventory.identity.infrastructure;

import com.smartfarm.inventory.identity.domain.IdentityModels.Membership;
import com.smartfarm.inventory.identity.domain.IdentityModels.RefreshSession;
import com.smartfarm.inventory.identity.domain.IdentityModels.User;
import java.nio.ByteBuffer;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

@Repository
public class JdbcIdentityRepository {
    private final JdbcTemplate jdbc;

    public JdbcIdentityRepository(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public Optional<User> findUserByUsername(String username) {
        return jdbc.query("SELECT * FROM app_user WHERE username = ?", this::mapUser, username).stream().findFirst();
    }

    public Optional<User> findUserBySubjectId(String subjectId) {
        return jdbc.query("SELECT * FROM app_user WHERE subject_id = ?", this::mapUser, subjectId).stream().findFirst();
    }

    public Optional<User> findUserById(UUID userId) {
        return jdbc.query("SELECT * FROM app_user WHERE id = ?", this::mapUser, bytes(userId)).stream().findFirst();
    }

    public List<Membership> memberships(String subjectId) {
        return jdbc.query("""
                SELECT m.organization_id, o.code, o.name, m.role_key
                FROM organization_membership m
                JOIN farm_organization o ON o.id = m.organization_id
                WHERE m.subject_id = ? AND m.enabled = TRUE AND o.enabled = TRUE
                ORDER BY o.code, m.role_key
                """, (resultSet, rowNumber) -> new Membership(
                readUuid(resultSet, "organization_id"), resultSet.getString("code"),
                resultSet.getString("name"), resultSet.getString("role_key")), subjectId);
    }

    public void touchLastAuthenticated(UUID userId) {
        jdbc.update("UPDATE app_user SET last_authenticated_at = CURRENT_TIMESTAMP(6) WHERE id = ?", bytes(userId));
    }

    public void insertRefreshSession(UUID sessionId, UUID userId, UUID organizationId, String tokenHash, Instant expiresAt, UUID rotatedFromId) {
        jdbc.update("""
                INSERT INTO auth_refresh_session
                  (id, user_id, active_organization_id, token_hash, expires_at, rotated_from_id)
                VALUES (?, ?, ?, ?, ?, ?)
                """, bytes(sessionId), bytes(userId), bytes(organizationId), tokenHash,
                java.sql.Timestamp.from(expiresAt), rotatedFromId == null ? null : bytes(rotatedFromId));
    }

    public Optional<RefreshSession> lockRefreshSession(String tokenHash) {
        return jdbc.query("SELECT * FROM auth_refresh_session WHERE token_hash = ? FOR UPDATE", this::mapSession, tokenHash)
                .stream().findFirst();
    }

    public void revokeRefreshSession(UUID sessionId) {
        jdbc.update("UPDATE auth_refresh_session SET revoked_at = CURRENT_TIMESTAMP(6) WHERE id = ? AND revoked_at IS NULL", bytes(sessionId));
    }

    public boolean isMembershipActive(String subjectId, UUID organizationId) {
        Integer count = jdbc.queryForObject("""
                SELECT COUNT(*) FROM organization_membership m
                JOIN farm_organization o ON o.id = m.organization_id
                WHERE m.subject_id = ? AND m.organization_id = ? AND m.enabled = TRUE AND o.enabled = TRUE
                """, Integer.class, subjectId, bytes(organizationId));
        return count != null && count > 0;
    }

    private User mapUser(ResultSet resultSet, int rowNumber) throws SQLException {
        return new User(readUuid(resultSet, "id"), resultSet.getString("subject_id"), resultSet.getString("username"),
                resultSet.getString("display_name"), resultSet.getString("password_hash"), resultSet.getBoolean("enabled"));
    }

    private RefreshSession mapSession(ResultSet resultSet, int rowNumber) throws SQLException {
        java.sql.Timestamp revokedAt = resultSet.getTimestamp("revoked_at");
        return new RefreshSession(readUuid(resultSet, "id"), readUuid(resultSet, "user_id"),
                readUuid(resultSet, "active_organization_id"), resultSet.getTimestamp("expires_at").toInstant(),
                revokedAt == null ? null : revokedAt.toInstant());
    }

    private static byte[] bytes(UUID value) {
        return ByteBuffer.allocate(16).putLong(value.getMostSignificantBits()).putLong(value.getLeastSignificantBits()).array();
    }

    private static UUID readUuid(ResultSet resultSet, String field) throws SQLException {
        ByteBuffer value = ByteBuffer.wrap(resultSet.getBytes(field));
        return new UUID(value.getLong(), value.getLong());
    }
}
