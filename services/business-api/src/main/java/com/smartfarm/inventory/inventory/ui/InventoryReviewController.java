package com.smartfarm.inventory.inventory.ui;

import com.smartfarm.inventory.common.CorrelationIdFilter;
import com.smartfarm.inventory.inventory.application.InventoryReviewService;
import com.smartfarm.inventory.inventory.application.InventoryReviewService.AggregateInventoryReport;
import com.smartfarm.inventory.inventory.application.InventoryReviewService.DailyInventoryRecord;
import com.smartfarm.inventory.inventory.application.InventoryReviewService.InventorySessionView;
import com.smartfarm.inventory.inventory.application.InventoryReviewService.NearDuplicateReviewView;
import com.smartfarm.inventory.inventory.application.InventoryReviewService.InventoryTaskView;
import jakarta.servlet.http.HttpServletRequest;
import java.time.Instant;
import jakarta.validation.Valid;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.Size;
import java.time.LocalDate;
import java.util.List;
import java.util.UUID;
import org.springframework.core.io.InputStreamResource;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.DeleteMapping;
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
@RequestMapping("/api/v1")
public class InventoryReviewController {
    private final InventoryReviewService service;

    public InventoryReviewController(InventoryReviewService service) {
        this.service = service;
    }

    @GetMapping("/review/near-duplicates")
    List<NearDuplicateReviewView> nearDuplicates() {
        return service.nearDuplicates();
    }

    @GetMapping("/inventory-tasks")
    List<InventoryTaskView> tasks(@RequestParam LocalDate businessDate) {
        return service.tasks(businessDate);
    }

    @GetMapping("/inventory-reports/daily")
    List<DailyInventoryRecord> dailyReport(@RequestParam LocalDate businessDate) {
        return service.dailyReport(businessDate);
    }

    @GetMapping("/inventory-reports/aggregate")
    AggregateInventoryReport aggregateReport(
            @RequestParam UUID penId,
            @RequestParam LocalDate from,
            @RequestParam LocalDate to) {
        return service.aggregateReport(penId, from, to);
    }

    @GetMapping("/inventory-sessions/{sessionId}")
    InventorySessionView session(@PathVariable UUID sessionId) {
        return service.session(sessionId);
    }

    @GetMapping("/inventory-sessions/{sessionId}/media")
    List<InventoryReviewService.MediaEvidenceView> sessionMedia(@PathVariable UUID sessionId) {
        return service.sessionMedia(sessionId);
    }

    @GetMapping("/media-assets/{assetId}/content")
    ResponseEntity<InputStreamResource> evidenceContent(@PathVariable UUID assetId) {
        InventoryReviewService.MediaContent content = service.evidenceContent(assetId);
        return ResponseEntity.ok().contentType(MediaType.parseMediaType(content.contentType()))
                .contentLength(content.byteSize()).body(new InputStreamResource(content.stream()));
    }

    @GetMapping("/audit-events")
    List<InventoryReviewService.AuditEventView> auditEvents(
            @RequestParam(required = false) Instant before,
            @RequestParam(defaultValue = "50") @Min(1) @Max(100) int limit) {
        return service.auditEvents(before == null ? Instant.now().plusSeconds(1) : before, limit);
    }

    @PostMapping("/inventory-sessions/{sessionId}/confirm")
    InventorySessionView confirm(
            @PathVariable UUID sessionId,
            @RequestHeader("X-Idempotency-Key") UUID idempotencyKey,
            @Valid @RequestBody ConfirmInventoryRequest request,
            HttpServletRequest servletRequest) {
        return service.confirm(sessionId, request.confirmedCount(), request.reason(), idempotencyKey,
                correlationId(servletRequest));
    }

    @PostMapping("/review/near-duplicates/{reviewId}/resolve")
    InventoryReviewService.NearDuplicateReviewView resolveNearDuplicate(
            @PathVariable UUID reviewId,
            @RequestHeader("X-Idempotency-Key") UUID idempotencyKey,
            @Valid @RequestBody ResolveNearDuplicateRequest request,
            HttpServletRequest servletRequest) {
        return service.resolveNearDuplicate(reviewId, request.reason(), idempotencyKey, correlationId(servletRequest));
    }

    @DeleteMapping("/media-assets/{assetId}")
    ResponseEntity<Void> deleteUnlockedEvidence(
            @PathVariable UUID assetId,
            @RequestHeader("X-Idempotency-Key") UUID idempotencyKey,
            HttpServletRequest servletRequest) {
        service.deleteUnlockedEvidence(assetId, idempotencyKey, correlationId(servletRequest));
        return ResponseEntity.noContent().build();
    }

    @PostMapping("/media-assets/{assetId}/override-delete")
    ResponseEntity<Void> overrideDelete(
            @PathVariable UUID assetId,
            @RequestHeader("X-Idempotency-Key") UUID idempotencyKey,
            @Valid @RequestBody OverrideDeleteRequest request,
            HttpServletRequest servletRequest) {
        service.overrideDelete(assetId, request.reason(), idempotencyKey, correlationId(servletRequest));
        return ResponseEntity.ok().build();
    }

    private static String correlationId(HttpServletRequest request) {
        Object value = request.getAttribute(CorrelationIdFilter.ATTRIBUTE);
        return value == null ? "unknown" : value.toString();
    }

    record ConfirmInventoryRequest(@Min(0) int confirmedCount, @Size(min = 8, max = 500) String reason) {
    }

    record OverrideDeleteRequest(@Size(min = 8, max = 500) String reason) {
    }

    record ResolveNearDuplicateRequest(@Size(min = 8, max = 500) String reason) {
    }
}
