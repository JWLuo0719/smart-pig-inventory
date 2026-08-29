package com.smartfarm.inventory.inventory.application;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.smartfarm.inventory.capture.infrastructure.StagedObjectStorage;
import com.smartfarm.inventory.inventory.infrastructure.JdbcInventoryReviewRepository;
import com.smartfarm.inventory.inventory.infrastructure.JdbcInventoryReviewRepository.ConfirmedCountRow;
import com.smartfarm.inventory.inventory.infrastructure.JdbcInventoryReviewRepository.MediaRow;
import com.smartfarm.inventory.inventory.infrastructure.JdbcInventoryReviewRepository.NearDuplicateRow;
import com.smartfarm.inventory.inventory.infrastructure.JdbcInventoryReviewRepository.TaskRow;
import com.smartfarm.inventory.inventory.infrastructure.JdbcInventoryReviewRepository.SessionRow;
import com.smartfarm.inventory.inventory.infrastructure.SecurityReviewActor;
import java.time.LocalDate;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class InventoryReviewServiceTest {
    @Mock private JdbcInventoryReviewRepository repository;
    @Mock private SecurityReviewActor actor;
    @Mock private StagedObjectStorage objectStorage;

    private InventoryReviewService service;
    private UUID sessionId;
    private UUID organizationId;

    @BeforeEach
    void setUp() {
        service = new InventoryReviewService(repository, actor, objectStorage);
        sessionId = UUID.randomUUID();
        organizationId = UUID.randomUUID();
    }

    @Test
    void manualConfirmationLocksEvidenceAndCreatesAnAuditEvent() {
        UUID idempotencyKey = UUID.randomUUID();
        SessionRow review = session("review_required", 7, null, null);
        SessionRow confirmed = session("confirmed", 7, 9, idempotencyKey.toString());
        when(repository.lockSession(sessionId)).thenReturn(Optional.of(review));
        when(repository.findSession(sessionId)).thenReturn(Optional.of(confirmed));
        when(actor.subjectId()).thenReturn("reviewer-1");

        InventoryReviewService.InventorySessionView result = service.confirm(
                sessionId, 9, "现场遮挡后人工复核确认", idempotencyKey, "corr-1");

        assertThat(result.status()).isEqualTo("confirmed");
        assertThat(result.count()).isEqualTo(9);
        assertThat(result.rawModelCount()).isEqualTo(7);
        assertThat(result.inferenceSource()).isEqualTo("manual");
        verify(actor).assertCanConfirm(organizationId);
        verify(repository).confirm(review, 9, idempotencyKey, "reviewer-1");
        verify(repository).lockEvidence(sessionId);
        verify(repository).insertAudit(eq(organizationId), eq("reviewer-1"), eq("inventory.confirmed"),
                eq("inventory_session"), eq(sessionId), eq("现场遮挡后人工复核确认"), any(), any(), eq("corr-1"));
    }

    @Test
    void preventsTwoConfirmedSessionsForTheSamePenAndBusinessDate() {
        SessionRow review = session("review_required", 7, null, null);
        when(repository.lockSession(sessionId)).thenReturn(Optional.of(review));
        when(repository.hasOtherConfirmedSession(review.penId(), review.businessDate(), review.id())).thenReturn(true);

        assertThatThrownBy(() -> service.confirm(sessionId, 7, null, UUID.randomUUID(), "corr-1"))
                .isInstanceOf(InventoryException.class)
                .hasMessageContaining("already confirmed");

        verify(repository, never()).confirm(any(), eq(7), any(), any());
    }

    @Test
    void derivesPendingTasksAndConfirmedOnlyAggregateReport() {
        UUID penId = UUID.randomUUID();
        LocalDate businessDate = LocalDate.of(2026, 8, 27);
        when(actor.activeOrganizationId()).thenReturn(organizationId);
        when(repository.listTasks(organizationId, businessDate)).thenReturn(List.of(
                new TaskRow(penId, "B01", "Building", "P01", "Pen", null, null, null)));
        when(repository.organizationForPen(penId)).thenReturn(Optional.of(organizationId));
        when(repository.confirmedCounts(penId, businessDate.minusDays(2), businessDate)).thenReturn(List.of(
                new ConfirmedCountRow(businessDate.minusDays(2), 10),
                new ConfirmedCountRow(businessDate, 13)));

        var tasks = service.tasks(businessDate);
        var report = service.aggregateReport(penId, businessDate.minusDays(2), businessDate);

        assertThat(tasks).singleElement().satisfies(task -> assertThat(task.status()).isEqualTo("pending"));
        assertThat(report.rawMean()).isEqualByComparingTo("11.5000");
        assertThat(report.roundedCount()).isEqualTo(12);
        assertThat(report.includedDates()).containsExactly("2026-08-25", "2026-08-27");
    }

    @Test
    void resolvesNearDuplicateWithoutDeletingEvidenceAndWritesAuditEvent() {
        UUID reviewId = UUID.randomUUID();
        UUID sourceMediaId = UUID.randomUUID();
        UUID candidateMediaId = UUID.randomUUID();
        NearDuplicateRow open = new NearDuplicateRow(reviewId, organizationId, sessionId, sourceMediaId, candidateMediaId,
                3, "open", java.time.Instant.parse("2026-08-27T00:00:00Z"), null, null);
        NearDuplicateRow resolved = new NearDuplicateRow(reviewId, organizationId, sessionId, sourceMediaId, candidateMediaId,
                3, "resolved", java.time.Instant.parse("2026-08-27T00:00:00Z"),
                java.time.Instant.parse("2026-08-27T00:01:00Z"), "00000000-0000-4000-8000-000000000001");
        when(repository.lockNearDuplicate(reviewId)).thenReturn(Optional.of(open), Optional.of(resolved));
        when(actor.subjectId()).thenReturn("reviewer-1");

        var result = service.resolveNearDuplicate(reviewId, "同一合成测试卡重复采集", UUID.fromString("00000000-0000-4000-8000-000000000001"), "corr-1");

        assertThat(result.state()).isEqualTo("resolved");
        verify(actor).assertCanConfirm(organizationId);
        verify(repository).resolveNearDuplicate(reviewId, UUID.fromString("00000000-0000-4000-8000-000000000001"));
        verify(repository).insertAudit(eq(organizationId), eq("reviewer-1"), eq("near_duplicate.resolved"),
                eq("near_duplicate_review"), eq(reviewId), eq("同一合成测试卡重复采集"), any(), any(), eq("corr-1"));
    }

    @Test
    void rejectsOrdinaryDeletionOfConfirmedEvidence() {
        UUID assetId = UUID.randomUUID();
        when(repository.lockMediaByAssetId(assetId)).thenReturn(Optional.of(
                new MediaRow(UUID.randomUUID(), assetId, organizationId, true, false)));

        assertThatThrownBy(() -> service.deleteUnlockedEvidence(assetId, UUID.randomUUID(), "corr-1"))
                .isInstanceOf(InventoryException.class)
                .hasMessageContaining("locked");

        verify(repository, never()).softDelete(any(), any());
    }

    @Test
    void requiresAReasonWhenNoCandidateCountExists() {
        when(repository.lockSession(sessionId)).thenReturn(Optional.of(session("review_required", null, null, null)));

        assertThatThrownBy(() -> service.confirm(sessionId, 9, null, UUID.randomUUID(), "corr-1"))
                .isInstanceOf(InventoryException.class)
                .hasMessageContaining("reason is required");

        verify(repository, never()).confirm(any(), eq(9), any(), any());
        verify(repository, never()).lockEvidence(any());
    }

    private SessionRow session(String status, Integer candidate, Integer confirmed, String idempotencyKey) {
        return new SessionRow(sessionId, UUID.randomUUID(), organizationId, LocalDate.of(2026, 8, 27), status,
                candidate, confirmed, idempotencyKey, "test-model", "1.0.0", "a".repeat(64), "http-v1",
                "test-provider", List.of("Provider requires review"));
    }
}
