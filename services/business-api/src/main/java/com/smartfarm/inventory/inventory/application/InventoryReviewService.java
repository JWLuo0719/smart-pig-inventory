package com.smartfarm.inventory.inventory.application;

import com.smartfarm.inventory.capture.infrastructure.StagedObjectStorage;
import com.smartfarm.inventory.inventory.infrastructure.JdbcInventoryReviewRepository;
import com.smartfarm.inventory.inventory.domain.InventoryAggregationPolicy;
import com.smartfarm.inventory.inventory.infrastructure.JdbcInventoryReviewRepository.MediaRow;
import com.smartfarm.inventory.inventory.infrastructure.JdbcInventoryReviewRepository.SessionRow;
import com.smartfarm.inventory.inventory.infrastructure.SecurityReviewActor;
import java.io.InputStream;
import java.math.BigDecimal;
import java.time.Instant;
import java.time.LocalDate;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class InventoryReviewService {
    private final JdbcInventoryReviewRepository repository;
    private final SecurityReviewActor actor;
    private final StagedObjectStorage objectStorage;

    public InventoryReviewService(JdbcInventoryReviewRepository repository, SecurityReviewActor actor,
            StagedObjectStorage objectStorage) {
        this.repository = repository;
        this.actor = actor;
        this.objectStorage = objectStorage;
    }

    @Transactional(readOnly = true)
    public List<NearDuplicateReviewView> nearDuplicates() {
        UUID organizationId = actor.activeOrganizationId();
        actor.assertCanConfirm(organizationId);
        return repository.listOpenNearDuplicates(organizationId).stream().map(this::nearDuplicateView).toList();
    }

    @Transactional
    public NearDuplicateReviewView resolveNearDuplicate(UUID reviewId, String reason, UUID idempotencyKey,
            String correlationId) {
        String normalizedReason = normalizeReason(reason);
        if (normalizedReason == null) throw InventoryException.invalid("Resolving a near-duplicate warning requires a reason");
        var review = repository.lockNearDuplicate(reviewId).orElseThrow(InventoryException::notFound);
        actor.assertCanConfirm(review.organizationId());
        if ("resolved".equals(review.state())) {
            if (idempotencyKey.toString().equals(review.resolutionIdempotencyKey())) return nearDuplicateView(review);
            throw InventoryException.conflict("The near-duplicate warning has already been resolved");
        }
        repository.resolveNearDuplicate(reviewId, idempotencyKey);
        repository.insertAudit(review.organizationId(), actor.subjectId(), "near_duplicate.resolved", "near_duplicate_review",
                reviewId, normalizedReason, Map.of("state", "open", "hammingDistance", review.hammingDistance()),
                Map.of("state", "resolved", "mediaRetained", true), correlationId);
        return nearDuplicateView(repository.lockNearDuplicate(reviewId).orElseThrow(InventoryException::notFound));
    }

    @Transactional(readOnly = true)
    public List<InventoryTaskView> tasks(LocalDate businessDate) {
        UUID organizationId = actor.activeOrganizationId();
        actor.assertCanView(organizationId);
        return repository.listTasks(organizationId, businessDate).stream()
                .map(row -> new InventoryTaskView(row.penId(), row.buildingCode(), row.buildingName(), row.penCode(),
                        row.penName(), businessDate.toString(), row.sessionId(),
                        row.status() == null ? "pending" : row.status(), row.confirmedCount()))
                .toList();
    }

    @Transactional(readOnly = true)
    public List<DailyInventoryRecord> dailyReport(LocalDate businessDate) {
        UUID organizationId = actor.activeOrganizationId();
        actor.assertCanView(organizationId);
        return repository.listConfirmedForDate(organizationId, businessDate).stream()
                .map(row -> new DailyInventoryRecord(row.sessionId(), row.penId(), row.buildingCode(), row.buildingName(),
                        row.penCode(), row.penName(), row.businessDate().toString(), row.confirmedCount()))
                .toList();
    }

    @Transactional(readOnly = true)
    public AggregateInventoryReport aggregateReport(UUID penId, LocalDate from, LocalDate to) {
        if (from.isAfter(to)) {
            throw InventoryException.invalid("The aggregate report start date must not be after its end date");
        }
        UUID organizationId = repository.organizationForPen(penId).orElseThrow(InventoryException::notFound);
        actor.assertCanView(organizationId);
        List<JdbcInventoryReviewRepository.ConfirmedCountRow> rows = repository.confirmedCounts(penId, from, to);
        InventoryAggregationPolicy.InventorySummary summary = InventoryAggregationPolicy.summarizeConfirmedCounts(
                rows.stream().map(JdbcInventoryReviewRepository.ConfirmedCountRow::confirmedCount).toList());
        return new AggregateInventoryReport(penId, from.toString(), to.toString(), summary.rawMean(), summary.roundedCount(),
                rows.stream().map(row -> row.businessDate().toString()).toList());
    }

    @Transactional(readOnly = true)
    public InventorySessionView session(UUID sessionId) {
        SessionRow session = repository.findSession(sessionId).orElseThrow(InventoryException::notFound);
        actor.assertCanView(session.organizationId());
        return view(session);
    }

    @Transactional(readOnly = true)
    public List<MediaEvidenceView> sessionMedia(UUID sessionId) {
        SessionRow session = repository.findSession(sessionId).orElseThrow(InventoryException::notFound);
        actor.assertCanView(session.organizationId());
        return repository.listSessionMedia(sessionId).stream().map(this::mediaView).toList();
    }

    @Transactional(readOnly = true)
    public MediaContent evidenceContent(UUID assetId) {
        var media = repository.findMediaEvidence(assetId).orElseThrow(InventoryException::notFound);
        actor.assertCanView(media.organizationId());
        if (media.deleted()) throw InventoryException.notFound();
        return new MediaContent(media.contentType(), media.byteSize(), objectStorage.open(media.storageKey()));
    }

    @Transactional(readOnly = true)
    public List<AuditEventView> auditEvents(Instant before, int limit) {
        UUID organizationId = actor.activeOrganizationId();
        actor.assertCanAudit(organizationId);
        return repository.listAuditEvents(organizationId, before, limit).stream()
                .map(row -> new AuditEventView(row.id(), row.actorId(), row.action(), row.targetType(), row.targetId(),
                        row.reason(), row.before(), row.after(), row.correlationId(), row.createdAt().toString()))
                .toList();
    }

    @Transactional
    public InventorySessionView confirm(UUID sessionId, int confirmedCount, String reason, UUID idempotencyKey,
            String correlationId) {
        SessionRow session = repository.lockSession(sessionId).orElseThrow(InventoryException::notFound);
        actor.assertCanConfirm(session.organizationId());
        if ("confirmed".equals(session.status())) {
            if (idempotencyKey.toString().equals(session.confirmationIdempotencyKey())) {
                return view(session);
            }
            throw InventoryException.conflict("The inventory session has already been confirmed");
        }
        if (!"review_required".equals(session.status())) {
            throw InventoryException.conflict("Only a session requiring review can be confirmed");
        }
        // Serialize confirmation per pen so two concurrent review decisions cannot both become final.
        repository.lockPen(session.penId());
        if (repository.hasOtherConfirmedSession(session.penId(), session.businessDate(), session.id())) {
            throw InventoryException.conflict(
                    "Another inventory session is already confirmed for this pen and business date; use an audited correction workflow");
        }
        String normalizedReason = normalizeReason(reason);
        if ((session.candidateCount() == null || session.candidateCount() != confirmedCount) && normalizedReason == null) {
            throw InventoryException.invalid("A reason is required when manually confirming or changing the candidate count");
        }

        repository.confirm(session, confirmedCount, idempotencyKey, actor.subjectId());
        repository.lockEvidence(session.id());
        repository.insertAudit(session.organizationId(), actor.subjectId(), "inventory.confirmed", "inventory_session", session.id(),
                normalizedReason, sessionSnapshot(session), confirmationSnapshot(confirmedCount), correlationId);
        return session(session.id());
    }

    @Transactional
    public void deleteUnlockedEvidence(UUID assetId, UUID idempotencyKey, String correlationId) {
        MediaRow media = repository.lockMediaByAssetId(assetId).orElseThrow(InventoryException::notFound);
        actor.assertCanView(media.organizationId());
        if (media.locked()) {
            throw InventoryException.conflict("Confirmed inventory evidence is locked and requires an administrator override");
        }
        if (media.deleted()) {
            if (idempotencyKey.toString().equals(repository.findDeleteIdempotencyKey(media.id()).orElse(null))) {
                return;
            }
            throw InventoryException.conflict("The media evidence has already been deleted");
        }
        repository.softDelete(media, idempotencyKey);
        repository.insertAudit(media.organizationId(), actor.subjectId(), "media.deleted", "media_asset", media.assetId(),
                null, mediaSnapshot(media), Map.of("state", "deleted"), correlationId);
    }

    @Transactional
    public void overrideDelete(UUID assetId, String reason, UUID idempotencyKey, String correlationId) {
        String normalizedReason = normalizeReason(reason);
        if (normalizedReason == null) {
            throw InventoryException.invalid("An administrative evidence deletion requires a reason");
        }
        MediaRow media = repository.lockMediaByAssetId(assetId).orElseThrow(InventoryException::notFound);
        actor.assertCanOverrideDelete(media.organizationId());
        if (media.deleted()) {
            if (idempotencyKey.toString().equals(repository.findDeleteIdempotencyKey(media.id()).orElse(null))) {
                return;
            }
            throw InventoryException.conflict("The media evidence has already been deleted by an administrative override");
        }
        repository.softDelete(media, idempotencyKey);
        repository.insertAudit(media.organizationId(), actor.subjectId(), "media.override_deleted", "media_asset", media.assetId(),
                normalizedReason, mediaSnapshot(media), Map.of("state", "deleted"), correlationId);
    }

    private NearDuplicateReviewView nearDuplicateView(JdbcInventoryReviewRepository.NearDuplicateRow row) {
        return new NearDuplicateReviewView(row.id(), row.sessionId(), row.sourceMediaId(), row.candidateMediaId(),
                row.hammingDistance(), row.state(), row.createdAt().toString(),
                row.resolvedAt() == null ? null : row.resolvedAt().toString());
    }

    private MediaEvidenceView mediaView(JdbcInventoryReviewRepository.MediaEvidenceRow row) {
        return new MediaEvidenceView(row.assetId(), row.viewPosition(), row.contentType(), row.byteSize(), row.state(),
                row.locked(), row.deleted());
    }

    private InventorySessionView view(SessionRow row) {
        Integer count = row.confirmedCount() != null ? row.confirmedCount() : row.candidateCount();
        String source = row.inferenceSource();
        if (row.confirmedCount() != null && (row.candidateCount() == null || !row.confirmedCount().equals(row.candidateCount()))) {
            source = "manual";
        } else if (source != null && !"device".equals(source) && !"manual".equals(source)) {
            source = "server";
        }
        ModelIdentity model = row.modelKey() == null ? null
                : new ModelIdentity(row.modelKey(), row.modelVersion(), row.modelChecksum(), row.adapterVersion());
        return new InventorySessionView(row.id(), row.penId(), row.businessDate().toString(), row.status(), count,
                row.candidateCount(), source, model, row.warnings());
    }

    private static String normalizeReason(String reason) {
        if (reason == null || reason.isBlank()) return null;
        String normalized = reason.trim();
        if (normalized.length() < 8 || normalized.length() > 500) {
            throw InventoryException.invalid("A reason must contain between 8 and 500 characters");
        }
        return normalized;
    }

    private static Map<String, Object> sessionSnapshot(SessionRow session) {
        Map<String, Object> snapshot = new LinkedHashMap<>();
        snapshot.put("status", session.status());
        snapshot.put("candidateCount", session.candidateCount());
        snapshot.put("confirmedCount", session.confirmedCount());
        return snapshot;
    }

    private static Map<String, Object> confirmationSnapshot(int confirmedCount) {
        return Map.of("status", "confirmed", "confirmedCount", confirmedCount, "evidenceLocked", true);
    }

    private static Map<String, Object> mediaSnapshot(MediaRow media) {
        return Map.of("assetId", media.assetId().toString(), "locked", media.locked(),
                "state", media.locked() ? "locked" : "submitted");
    }

    public record NearDuplicateReviewView(UUID id, UUID sessionId, UUID sourceMediaId, UUID candidateMediaId,
            int hammingDistance, String state, String createdAt, String resolvedAt) {
    }

    public record MediaEvidenceView(UUID assetId, String viewPosition, String contentType, long byteSize, String state,
            boolean locked, boolean deleted) {
    }

    public record MediaContent(String contentType, long byteSize, InputStream stream) {
    }

    public record AuditEventView(UUID id, String actorId, String action, String targetType, String targetId,
            String reason, Object before, Object after, String correlationId, String createdAt) {
    }

    public record InventoryTaskView(UUID penId, String buildingCode, String buildingName, String penCode, String penName,
            String businessDate, UUID sessionId, String status, Integer confirmedCount) {
    }

    public record DailyInventoryRecord(UUID sessionId, UUID penId, String buildingCode, String buildingName, String penCode,
            String penName, String businessDate, int confirmedCount) {
    }

    public record AggregateInventoryReport(UUID penId, String from, String to, BigDecimal rawMean, Integer roundedCount,
            List<String> includedDates) {
    }

    public record InventorySessionView(UUID id, UUID penId, String businessDate, String status, Integer count,
            Integer rawModelCount, String inferenceSource, ModelIdentity model, List<String> warnings) {
    }

    public record ModelIdentity(String modelKey, String version, String checksum, String adapterVersion) {
    }
}
