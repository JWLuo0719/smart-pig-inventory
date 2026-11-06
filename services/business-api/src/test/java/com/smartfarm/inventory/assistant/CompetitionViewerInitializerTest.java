package com.smartfarm.inventory.assistant;

import static org.assertj.core.api.Assertions.*;
import static org.mockito.Mockito.*;
import com.smartfarm.inventory.identity.infrastructure.CompetitionViewerInitializer;
import java.time.Instant;
import java.util.List;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.security.crypto.password.PasswordEncoder;

class CompetitionViewerInitializerTest {
    private final JdbcTemplate jdbc = mock(JdbcTemplate.class);
    private final PasswordEncoder passwords = mock(PasswordEncoder.class);
    private final String expiry = Instant.now().plusSeconds(86400).toString();
    @Test void requiresExplicitSecureSettingsAndBoundedExpiry() {
        assertThatThrownBy(() -> new CompetitionViewerInitializer(jdbc, passwords, false, "viewer", "long-fixture-password", "COMP", expiry)).isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> new CompetitionViewerInitializer(jdbc, passwords, true, "viewer", "short", "COMP", expiry)).isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> new CompetitionViewerInitializer(jdbc, passwords, true, "viewer", "long-fixture-password", "COMP", "")).isInstanceOf(IllegalArgumentException.class);
        verifyNoInteractions(jdbc);
    }
    @SuppressWarnings("unchecked")
    @Test void createsOnlyAViewerAndHashesPassword() {
        when(jdbc.query(startsWith("SELECT id FROM farm_organization"), any(RowMapper.class), eq("COMP"))).thenReturn(List.of(UUID.randomUUID()));
        when(jdbc.query(startsWith("SELECT subject_id"), any(RowMapper.class), eq("viewer"))).thenReturn(List.of());
        when(passwords.encode("long-fixture-password")).thenReturn("hashed-fixture");
        new CompetitionViewerInitializer(jdbc, passwords, true, "viewer", "long-fixture-password", "COMP", expiry).run(null);
        verify(jdbc).update(startsWith("INSERT INTO app_user"), any(), any(), eq("viewer"), eq("作品体验账号"), eq("hashed-fixture"));
        verify(jdbc).update(startsWith("INSERT INTO organization_membership"), any(), any(), any(), eq("COMPETITION_VIEWER"), any());
    }
    @SuppressWarnings("unchecked")
    @Test void refusesToRepurposeAnExistingPrivilegedUsername() throws Exception {
        UUID org = UUID.randomUUID();
        when(jdbc.query(startsWith("SELECT id FROM farm_organization"), any(RowMapper.class), eq("COMP"))).thenReturn(List.of(org));
        var user = mock(java.sql.ResultSet.class);
        when(user.getString("subject_id")).thenReturn("privileged"); when(user.getString("password_hash")).thenReturn("hash"); when(user.getBoolean("enabled")).thenReturn(true);
        doAnswer(invocation -> List.of(((RowMapper<?>) invocation.getArgument(1)).mapRow(user, 0)))
                .when(jdbc).query(startsWith("SELECT subject_id"), any(RowMapper.class), eq("viewer"));
        var membership = mock(java.sql.ResultSet.class);
        when(membership.getBytes("organization_id")).thenReturn(java.nio.ByteBuffer.allocate(16).putLong(org.getMostSignificantBits()).putLong(org.getLeastSignificantBits()).array());
        when(membership.getString("role_key")).thenReturn("FARM_ADMIN");
        doAnswer(invocation -> List.of(((RowMapper<?>) invocation.getArgument(1)).mapRow(membership, 0)))
                .when(jdbc).query(startsWith("SELECT organization_id"), any(RowMapper.class), eq("privileged"));
        when(passwords.matches("long-fixture-password", "hash")).thenReturn(true);
        assertThatThrownBy(() -> new CompetitionViewerInitializer(jdbc, passwords, true, "viewer", "long-fixture-password", "COMP", expiry).run(null))
                .isInstanceOf(IllegalStateException.class);
        verify(jdbc, never()).update(anyString(), any(Object[].class));
    }
}
