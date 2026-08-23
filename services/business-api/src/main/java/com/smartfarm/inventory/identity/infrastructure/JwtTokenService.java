package com.smartfarm.inventory.identity.infrastructure;

import com.smartfarm.inventory.identity.domain.IdentityModels.Membership;
import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.UUID;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.security.oauth2.jose.jws.MacAlgorithm;
import org.springframework.security.oauth2.jwt.JwsHeader;
import org.springframework.security.oauth2.jwt.JwtClaimsSet;
import org.springframework.security.oauth2.jwt.JwtEncoder;
import org.springframework.security.oauth2.jwt.JwtEncoderParameters;
import org.springframework.stereotype.Component;

@Component
@ConditionalOnProperty(name = "app.security.enabled", havingValue = "true", matchIfMissing = true)
public class JwtTokenService {
    private final JwtEncoder encoder;
    private final Duration accessTtl;
    private final String issuer;

    public JwtTokenService(
            JwtEncoder encoder,
            @Value("${app.security.access-token-ttl:PT15M}") Duration accessTtl,
            @Value("${app.security.jwt-issuer:pig-inventory-business-api}") String issuer) {
        this.encoder = encoder;
        this.accessTtl = accessTtl;
        this.issuer = issuer;
    }

    public IssuedAccessToken issue(String subjectId, UUID activeOrganizationId, List<Membership> memberships) {
        Instant issuedAt = Instant.now();
        Instant expiresAt = issuedAt.plus(accessTtl);
        List<String> roles = memberships.stream()
                .filter(membership -> membership.organizationId().equals(activeOrganizationId))
                .map(Membership::role)
                .distinct()
                .toList();
        JwtClaimsSet claims = JwtClaimsSet.builder()
                .issuer(issuer)
                .subject(subjectId)
                .issuedAt(issuedAt)
                .expiresAt(expiresAt)
                .claim("active_organization_id", activeOrganizationId.toString())
                .claim("roles", roles)
                .build();
        String value = encoder.encode(JwtEncoderParameters.from(
                JwsHeader.with(MacAlgorithm.HS256).build(), claims)).getTokenValue();
        return new IssuedAccessToken(value, expiresAt);
    }

    public record IssuedAccessToken(String value, Instant expiresAt) {
    }
}
