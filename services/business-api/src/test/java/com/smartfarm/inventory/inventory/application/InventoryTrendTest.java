package com.smartfarm.inventory.inventory.application;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;

import com.smartfarm.inventory.inventory.application.InventoryReviewService.InventoryTrend;
import com.smartfarm.inventory.inventory.application.InventoryReviewService.TrendPoint;
import com.smartfarm.inventory.inventory.infrastructure.JdbcInventoryReviewRepository.TrendRow;
import java.time.LocalDate;
import java.util.List;
import java.util.UUID;
import org.junit.jupiter.api.Test;

class InventoryTrendTest {

    private static final LocalDate FROM = LocalDate.of(2026, 9, 18);
    private static final LocalDate TO = LocalDate.of(2026, 9, 19);
    private static final UUID PEN_A = UUID.randomUUID();
    private static final UUID PEN_B = UUID.randomUUID();

    private static TrendRow row(LocalDate date, UUID penId, String penCode, String status,
            Integer confirmed, Integer candidate) {
        return new TrendRow(date, penId, "B01", penCode, penCode + "号栏舍", status, confirmed, candidate);
    }

    @Test
    void aggregatesTotalsAndPerPenSeriesAcrossDates() {
        InventoryTrend trend = InventoryReviewService.assembleTrend(FROM, TO, List.of(
                row(FROM, PEN_A, "01", "confirmed", 28, 28),
                row(FROM, PEN_B, "02", "confirmed", 30, 30),
                row(TO, PEN_A, "01", "review_required", null, 26)));
        assertEquals(TO, LocalDate.parse(trend.to()));
        assertEquals(2, trend.total().size());
        TrendPoint first = trend.total().get(0);
        assertEquals(58, first.confirmed());
        assertEquals(58, first.candidate());
        TrendPoint second = trend.total().get(1);
        assertNull(second.confirmed());
        assertEquals(26, second.candidate());
        assertEquals(2, trend.pens().size());
        assertEquals(28, trend.pens().get(0).points().get(0).confirmed());
        assertNull(trend.pens().get(0).points().get(1).confirmed());
        assertEquals("01 01号栏舍", trend.pens().get(0).penLabel());
    }

    @Test
    void emptyWindowStillProducesADenseAxis() {
        InventoryTrend trend = InventoryReviewService.assembleTrend(FROM, FROM.plusDays(2), List.of());
        assertEquals(3, trend.total().size());
        assertNull(trend.total().get(0).confirmed());
        assertEquals(0, trend.pens().size());
    }
}
