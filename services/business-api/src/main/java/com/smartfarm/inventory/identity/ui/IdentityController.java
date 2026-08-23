package com.smartfarm.inventory.identity.ui;

import com.smartfarm.inventory.identity.application.IdentityService;
import com.smartfarm.inventory.identity.domain.IdentityModels.CurrentUser;
import com.smartfarm.inventory.identity.domain.IdentityModels.TokenPair;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import java.util.UUID;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@Validated
@ConditionalOnProperty(name = "app.security.enabled", havingValue = "true", matchIfMissing = true)
@RequestMapping("/api/v1")
public class IdentityController {
    private final IdentityService service;

    public IdentityController(IdentityService service) {
        this.service = service;
    }

    @PostMapping("/auth/login")
    TokenPair login(
            @RequestHeader("X-Idempotency-Key") UUID idempotencyKey,
            @Valid @RequestBody LoginRequest request) {
        return service.login(request.username(), request.password());
    }

    @PostMapping("/auth/refresh")
    TokenPair refresh(
            @RequestHeader("X-Idempotency-Key") UUID idempotencyKey,
            @Valid @RequestBody RefreshTokenRequest request) {
        return service.refresh(request.refreshToken());
    }

    @PostMapping("/auth/logout")
    ResponseEntity<Void> logout(
            @RequestHeader("X-Idempotency-Key") UUID idempotencyKey,
            @AuthenticationPrincipal Jwt jwt,
            @Valid @RequestBody RefreshTokenRequest request) {
        service.logout(jwt.getSubject(), request.refreshToken());
        return ResponseEntity.noContent().build();
    }

    @GetMapping("/me")
    CurrentUser currentUser(@AuthenticationPrincipal Jwt jwt) {
        String organizationId = jwt.getClaimAsString("active_organization_id");
        if (organizationId == null) {
            throw new IllegalArgumentException("Token does not contain an active organization");
        }
        return service.currentUser(jwt.getSubject(), UUID.fromString(organizationId));
    }

    record LoginRequest(
            @NotBlank @Size(max = 128) String username,
            @NotBlank @Size(min = 8, max = 256) String password) {
    }

    record RefreshTokenRequest(@NotBlank @Size(min = 32, max = 2048) String refreshToken) {
    }
}
