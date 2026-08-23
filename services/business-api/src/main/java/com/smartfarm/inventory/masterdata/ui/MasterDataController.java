package com.smartfarm.inventory.masterdata.ui;

import com.smartfarm.inventory.masterdata.application.MasterDataService;
import com.smartfarm.inventory.masterdata.domain.MasterDataChanges;
import java.util.UUID;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@ConditionalOnProperty(name = "app.security.enabled", havingValue = "true", matchIfMissing = true)
@RequestMapping("/api/v1/master-data")
public class MasterDataController {
    private final MasterDataService service;

    public MasterDataController(MasterDataService service) {
        this.service = service;
    }

    @GetMapping("/changes")
    MasterDataChanges changes(@AuthenticationPrincipal Jwt jwt, @RequestParam(required = false) String cursor) {
        String organizationId = jwt.getClaimAsString("active_organization_id");
        if (organizationId == null) {
            throw new IllegalArgumentException("Token does not contain an active organization");
        }
        return service.changes(UUID.fromString(organizationId), cursor);
    }
}
