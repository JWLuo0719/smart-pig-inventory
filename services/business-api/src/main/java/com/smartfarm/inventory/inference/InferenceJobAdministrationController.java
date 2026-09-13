package com.smartfarm.inventory.inference;

import com.smartfarm.inventory.common.CorrelationIdFilter;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.Size;
import java.time.Instant;
import java.util.List;
import java.util.UUID;
import org.springframework.http.ResponseEntity;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@Validated
@RequestMapping("/api/v1/inference-jobs")
public class InferenceJobAdministrationController {
    private final InferenceJobAdministrationService service;

    public InferenceJobAdministrationController(InferenceJobAdministrationService service) {
        this.service = service;
    }

    @GetMapping("/failed")
    List<InferenceJobAdministrationService.FailedInferenceJobView> failedJobs(
            @RequestParam(required = false) Instant before,
            @RequestParam(defaultValue = "50") @Min(1) @Max(100) int limit) {
        return service.failedJobs(before == null ? Instant.now().plusSeconds(1) : before, limit);
    }

    @PostMapping("/{jobId}/retries")
    ResponseEntity<InferenceJobAdministrationService.RetryResult> retry(
            @PathVariable UUID jobId,
            @RequestHeader("X-Idempotency-Key") UUID idempotencyKey,
            @Valid @RequestBody RetryInferenceJobRequest request,
            HttpServletRequest servletRequest) {
        var outcome = service.retry(jobId, request.reason(), idempotencyKey, correlationId(servletRequest));
        return outcome.replayed()
                ? ResponseEntity.ok(outcome.result())
                : ResponseEntity.status(201).body(outcome.result());
    }

    private static String correlationId(HttpServletRequest request) {
        Object value = request.getAttribute(CorrelationIdFilter.ATTRIBUTE);
        return value == null ? "unknown" : value.toString();
    }

    record RetryInferenceJobRequest(@Size(min = 8, max = 500) String reason) {
    }
}
