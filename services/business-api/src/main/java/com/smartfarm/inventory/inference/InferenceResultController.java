package com.smartfarm.inventory.inference;

import jakarta.validation.Valid;
import java.util.UUID;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1/inference-jobs")
public class InferenceResultController {
    private final InferenceCallbackAuthenticator authenticator;
    private final InferenceResultService service;

    public InferenceResultController(InferenceCallbackAuthenticator authenticator, InferenceResultService service) {
        this.authenticator = authenticator;
        this.service = service;
    }

    @PutMapping("/{jobId}/result")
    ResponseEntity<Void> putResult(
            @PathVariable UUID jobId,
            @RequestHeader(value = "X-Inference-Service-Key", required = false) String serviceKey,
            @RequestHeader("X-Idempotency-Key") UUID ignoredIdempotencyKey,
            @Valid @RequestBody InferenceCallbackResult result) {
        authenticator.assertAuthorized(serviceKey);
        InferenceResultService.CallbackOutcome outcome = service.accept(jobId, result);
        return outcome == InferenceResultService.CallbackOutcome.CREATED
                ? ResponseEntity.noContent().build()
                : ResponseEntity.ok().build();
    }
}
