package com.smartfarm.inventory.identity.domain;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

public final class IdentityModels {
    private IdentityModels() {
    }

    public record User(UUID id, String subjectId, String username, String displayName, String passwordHash, boolean enabled) {
    }

    public record Membership(UUID organizationId, String organizationCode, String organizationName, String role) {
    }

    public record RefreshSession(UUID id, UUID userId, UUID organizationId, Instant expiresAt, Instant revokedAt) {
    }

    public record TokenPair(
            String accessToken,
            String refreshToken,
            String tokenType,
            Instant accessTokenExpiresAt,
            Instant refreshTokenExpiresAt) {
    }

    public record CurrentUser(
            String subjectId, String displayName, UUID activeOrganizationId, List<OrganizationMembership> memberships) {
    }

    public record OrganizationMembership(UUID organizationId, String organizationCode, String organizationName, List<String> roles) {
    }
}
