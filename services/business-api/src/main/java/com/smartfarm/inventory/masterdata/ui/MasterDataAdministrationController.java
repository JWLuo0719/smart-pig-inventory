package com.smartfarm.inventory.masterdata.ui;

import com.smartfarm.inventory.common.CorrelationIdFilter;
import com.smartfarm.inventory.masterdata.application.MasterDataAdministrationService;
import com.smartfarm.inventory.masterdata.application.MasterDataAdministrationService.Command;
import com.smartfarm.inventory.masterdata.domain.MasterDataChanges.NamedEntity;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotNull;
import java.util.UUID;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/v1/master-data")
public class MasterDataAdministrationController {
    private final MasterDataAdministrationService service;
    public MasterDataAdministrationController(MasterDataAdministrationService service) { this.service = service; }

    @PutMapping("/{entityType}/{entityId}")
    NamedEntity save(@PathVariable String entityType, @PathVariable UUID entityId,
            @RequestHeader("X-Idempotency-Key") UUID key, @Valid @RequestBody Request request, HttpServletRequest servlet) {
        return service.save(entityType, entityId, key,
                new Command(request.parentId(), request.code(), request.name(), request.enabled(), request.expectedVersion(), request.reason()),
                String.valueOf(servlet.getAttribute(CorrelationIdFilter.ATTRIBUTE)));
    }
    record Request(UUID parentId, String code, String name, @NotNull Boolean enabled, @NotNull Long expectedVersion, String reason) { }
}
