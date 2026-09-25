package com.smartfarm.inventory.inventory.application;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import com.smartfarm.inventory.inventory.application.AssistantInsightService.AssistantBrief;
import com.smartfarm.inventory.inventory.application.AssistantInsightService.Insight;
import com.smartfarm.inventory.inventory.infrastructure.JdbcAssistantInsightRepository.AssistantRow;
import com.smartfarm.inventory.inventory.infrastructure.JdbcAssistantInsightRepository.PenHistoryRow;
import java.time.LocalDate;
import java.util.List;
import java.util.UUID;
import org.junit.jupiter.api.Test;

class AssistantInsightServiceTest {

    private static final LocalDate DATE = LocalDate.of(2026, 9, 18);
    private static final UUID PEN = UUID.randomUUID();

    private static AssistantRow row(String status, Integer candidate, Integer confirmed,
                                    int detections, LocalDate lastDate, Integer lastCount) {
        return new AssistantRow(PEN, "B01", "1号栋", "01", "1号栏舍",
                status == null ? null : UUID.randomUUID(), status, candidate, confirmed,
                null, null, detections, List.of(), lastDate, lastCount);
    }

    @Test
    void emptyMasterDataProducesGuidance() {
        AssistantBrief brief = AssistantInsightService.build(DATE, List.of());
        assertEquals(1, brief.insights().size());
        assertEquals("EMPTY_MASTER_DATA", brief.insights().get(0).type());
        assertTrue(brief.brief().contains("栏舍台账"));
    }

    @Test
    void reviewRequiredWithHistoryShowsCandidateAndDelta() {
        AssistantBrief brief = AssistantInsightService.build(DATE, List.of(
                row("review_required", 27, null, 27, DATE.minusDays(3), 28)));
        Insight review = brief.insights().stream()
                .filter(insight -> "REVIEW_REQUIRED".equals(insight.type())).findFirst().orElseThrow();
        assertTrue(review.title().contains("候选 27"));
        assertTrue(review.detail().contains("-1"));
        assertTrue(review.detail().contains("28"));
        assertTrue(brief.brief().contains("待复核 1 栏"));
    }

    @Test
    void largeChangeIsMarkedActionable() {
        AssistantBrief brief = AssistantInsightService.build(DATE, List.of(
                row("review_required", 20, null, 20, DATE.minusDays(2), 30)));
        Insight review = brief.insights().stream()
                .filter(insight -> "REVIEW_REQUIRED".equals(insight.type())).findFirst().orElseThrow();
        assertEquals("action", review.severity());
        assertTrue(review.detail().contains("变化较大"));
    }

    @Test
    void missingCapturesAreGrouped() {
        AssistantBrief brief = AssistantInsightService.build(DATE, List.of(
                row("confirmed", 28, 28, 28, null, null),
                row(null, null, null, 0, null, null)));
        Insight pending = brief.insights().stream()
                .filter(insight -> "PENDING_CAPTURE".equals(insight.type())).findFirst().orElseThrow();
        assertTrue(pending.title().contains("尚未采集"));
        assertTrue(brief.brief().contains("已确认 1/2 栏"));
        assertTrue(brief.brief().contains("存栏合计 28 头"));
    }

    @Test
    void allConfirmedProducesSuccessSummary() {
        AssistantBrief brief = AssistantInsightService.build(DATE, List.of(
                row("confirmed", 28, 28, 28, null, null),
                row("confirmed", 30, 30, 30, null, null)));
        Insight summary = brief.insights().stream()
                .filter(insight -> "DAY_SUMMARY".equals(insight.type())).findFirst().orElseThrow();
        assertEquals("success", summary.severity());
        assertTrue(summary.detail().contains("58 头"));
    }

    @Test
    void failedInferenceAsksForManualCounting() {
        AssistantBrief brief = AssistantInsightService.build(DATE, List.of(
                new AssistantRow(PEN, "B01", "1号栋", "01", "1号栏舍", UUID.randomUUID(),
                        "review_required", null, null, "failed", "PROVIDER_HTTP_STATUS",
                        0, List.of(), null, null)));
        Insight review = brief.insights().stream()
                .filter(insight -> "REVIEW_REQUIRED".equals(insight.type())).findFirst().orElseThrow();
        assertTrue(review.title().contains("人工清点"));
        assertTrue(review.detail().contains("PROVIDER_HTTP_STATUS"));
    }

    @Test
    void countDropAgainstBaselineRaisesRiskCandidate() {
        AssistantBrief brief = AssistantInsightService.build(DATE,
                List.of(row("confirmed", 28, 20, 20, null, null)),
                List.of(
                        new PenHistoryRow(PEN, "01", "1号栏舍", "B01", "1号栋", DATE.minusDays(1), 30),
                        new PenHistoryRow(PEN, "01", "1号栏舍", "B01", "1号栋", DATE.minusDays(3), 28),
                        new PenHistoryRow(PEN, "01", "1号栏舍", "B01", "1号栋", DATE.minusDays(5), 30)));
        Insight risk = brief.insights().stream()
                .filter(insight -> "RISK_CANDIDATE".equals(insight.type())).findFirst().orElseThrow();
        assertEquals("action", risk.severity());
        assertTrue(risk.title().contains("下降"));
        assertTrue(risk.detail().contains("中位 30 头"));
        assertTrue(risk.detail().contains("不构成诊断"));
    }

    @Test
    void countRiseAgainstBaselineIsInfoOnly() {
        AssistantBrief brief = AssistantInsightService.build(DATE,
                List.of(row("confirmed", 28, 36, 36, null, null)),
                List.of(
                        new PenHistoryRow(PEN, "01", "1号栏舍", "B01", "1号栋", DATE.minusDays(1), 28),
                        new PenHistoryRow(PEN, "01", "1号栏舍", "B01", "1号栋", DATE.minusDays(2), 28)));
        Insight shift = brief.insights().stream()
                .filter(insight -> "BASELINE_SHIFT".equals(insight.type())).findFirst().orElseThrow();
        assertEquals("info", shift.severity());
        assertTrue(shift.title().contains("上升"));
    }

    @Test
    void normalVariationDoesNotRaiseRisk() {
        AssistantBrief brief = AssistantInsightService.build(DATE,
                List.of(row("confirmed", 28, 29, 29, null, null)),
                List.of(
                        new PenHistoryRow(PEN, "01", "1号栏舍", "B01", "1号栋", DATE.minusDays(1), 28),
                        new PenHistoryRow(PEN, "01", "1号栏舍", "B01", "1号栋", DATE.minusDays(2), 30)));
        assertTrue(brief.insights().stream()
                .noneMatch(insight -> "RISK_CANDIDATE".equals(insight.type())
                        || "BASELINE_SHIFT".equals(insight.type())));
    }

    @Test
    void longCaptureGapAsksForRecapture() {
        AssistantBrief brief = AssistantInsightService.build(DATE,
                List.of(row(null, null, null, 0, DATE.minusDays(5), 28)),
                List.of(new PenHistoryRow(PEN, "01", "1号栏舍", "B01", "1号栋", DATE.minusDays(5), 28)));
        Insight gap = brief.insights().stream()
                .filter(insight -> "CAPTURE_GAP".equals(insight.type())).findFirst().orElseThrow();
        assertEquals("action", gap.severity());
        assertTrue(gap.title().contains("5 天未采集"));
        assertTrue(gap.detail().contains("28 头"));
    }
}
