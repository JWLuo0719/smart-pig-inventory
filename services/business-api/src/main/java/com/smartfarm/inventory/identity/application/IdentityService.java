package com.smartfarm.inventory.identity.application;

import com.smartfarm.inventory.identity.domain.IdentityModels.CurrentUser;
import com.smartfarm.inventory.identity.domain.IdentityModels.Membership;
import com.smartfarm.inventory.identity.domain.IdentityModels.OrganizationMembership;
import com.smartfarm.inventory.identity.domain.IdentityModels.RefreshSession;
import com.smartfarm.inventory.identity.domain.IdentityModels.TokenPair;
import com.smartfarm.inventory.identity.domain.IdentityModels.User;
import com.smartfarm.inventory.identity.infrastructure.JdbcIdentityRepository;
import com.smartfarm.inventory.identity.infrastructure.JwtTokenService;
import com.smartfarm.inventory.identity.infrastructure.JwtTokenService.IssuedAccessToken;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.SecureRandom;
import java.time.Duration;
import java.time.Instant;
import java.util.Base64;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
@ConditionalOnProperty(name = "app.security.enabled", havingValue = "true", matchIfMissing = true)
public class IdentityService {
    private static final SecureRandom RANDOM = new SecureRandom();

    private final JdbcIdentityRepository repository;
    private final JwtTokenService tokenService;
    private final PasswordEncoder passwordEncoder;
    private final Duration refreshTtl;

    public IdentityService(
            JdbcIdentityRepository repository,
            JwtTokenService tokenService,
            PasswordEncoder passwordEncoder,
            @Value("${app.security.refresh-token-ttl:P7D}") Duration refreshTtl) {
        this.repository = repository;
        this.tokenService = tokenService;
        this.passwordEncoder = passwordEncoder;
        this.refreshTtl = refreshTtl;
    }

    @Transactional
    public TokenPair login(String username, String password) {
        User user = repository.findUserByUsername(username)
                .filter(User::enabled)
                .orElseThrow(() -> IdentityException.unauthorized("LOGIN_FAILED"));
        if (!passwordEncoder.matches(password, user.passwordHash())) {
            throw IdentityException.unauthorized("LOGIN_FAILED");
        }
        List<Membership> memberships = repository.memberships(user.subjectId());
        if (memberships.isEmpty()) {
            throw IdentityException.unauthorized("NO_ACTIVE_ORGANIZATION");
        }
        repository.touchLastAuthenticated(user.id());
        return issuePair(user, memberships, memberships.getFirst().organizationId(), null);
    }

    @Transactional
    public TokenPair refresh(String rawRefreshToken) {
        RefreshSession session = repository.lockRefreshSession(hash(rawRefreshToken))
                .orElseThrow(() -> IdentityException.unauthorized("REFRESH_TOKEN_INVALID"));
        if (session.revokedAt() != null) {
            throw IdentityException.conflict("REFRESH_TOKEN_REUSED");
        }
        if (!session.expiresAt().isAfter(Instant.now())) {
            repository.revokeRefreshSession(session.id());
            throw IdentityException.unauthorized("REFRESH_TOKEN_EXPIRED");
        }
        User user = repository.findUserById(session.userId())
                .filter(User::enabled)
                .orElseThrow(() -> IdentityException.unauthorized("REFRESH_TOKEN_INVALID"));
        List<Membership> memberships = repository.memberships(user.subjectId());
        if (memberships.stream().noneMatch(membership -> membership.organizationId().equals(session.organizationId()))) {
            repository.revokeRefreshSession(session.id());
            throw IdentityException.unauthorized("NO_ACTIVE_ORGANIZATION");
        }
        repository.revokeRefreshSession(session.id());
        return issuePair(user, memberships, session.organizationId(), session.id());
    }

    @Transactional
    public void logout(String subjectId, String rawRefreshToken) {
        RefreshSession session = repository.lockRefreshSession(hash(rawRefreshToken)).orElse(null);
        if (session == null) {
            return;
        }
        User user = repository.findUserById(session.userId()).orElse(null);
        if (user != null && user.subjectId().equals(subjectId)) {
            repository.revokeRefreshSession(session.id());
        }
    }

    public CurrentUser currentUser(String subjectId, UUID activeOrganizationId) {
        User user = repository.findUserBySubjectId(subjectId)
                .filter(User::enabled)
                .orElseThrow(() -> IdentityException.unauthorized("USER_DISABLED"));
        List<Membership> memberships = repository.memberships(user.subjectId());
        if (memberships.stream().noneMatch(membership -> membership.organizationId().equals(activeOrganizationId))) {
            throw IdentityException.unauthorized("ORGANIZATION_ACCESS_REVOKED");
        }
        Map<UUID, List<Membership>> byOrganization = new LinkedHashMap<>();
        for (Membership membership : memberships) {
            byOrganization.computeIfAbsent(membership.organizationId(), ignored -> new java.util.ArrayList<>()).add(membership);
        }
        List<OrganizationMembership> responseMemberships = byOrganization.values().stream()
                .map(group -> new OrganizationMembership(group.getFirst().organizationId(), group.getFirst().organizationCode(),
                        group.getFirst().organizationName(), group.stream().map(Membership::role).distinct().toList()))
                .toList();
        return new CurrentUser(user.subjectId(), user.displayName(), activeOrganizationId, responseMemberships);
    }

    private TokenPair issuePair(User user, List<Membership> memberships, UUID organizationId, UUID rotatedFromId) {
        IssuedAccessToken accessToken = tokenService.issue(user.subjectId(), organizationId, memberships);
        String refreshToken = newRefreshToken();
        Instant refreshExpiresAt = Instant.now().plus(refreshTtl);
        repository.insertRefreshSession(UUID.randomUUID(), user.id(), organizationId, hash(refreshToken), refreshExpiresAt, rotatedFromId);
        return new TokenPair(accessToken.value(), refreshToken, "Bearer", accessToken.expiresAt(), refreshExpiresAt);
    }

    private static String newRefreshToken() {
        byte[] bytes = new byte[32];
        RANDOM.nextBytes(bytes);
        return Base64.getUrlEncoder().withoutPadding().encodeToString(bytes);
    }

    private static String hash(String rawToken) {
        try {
            return java.util.HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256")
                    .digest(rawToken.getBytes(StandardCharsets.UTF_8)));
        } catch (Exception exception) {
            throw new IllegalStateException("SHA-256 is unavailable", exception);
        }
    }
}
