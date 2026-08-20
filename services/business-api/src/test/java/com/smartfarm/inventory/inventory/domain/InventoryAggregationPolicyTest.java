package com.smartfarm.inventory.inventory.domain;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;

import java.math.BigDecimal;
import java.util.List;
import org.junit.jupiter.api.Test;

class InventoryAggregationPolicyTest {
    @Test
    void averagesConfirmedDaysAndPreservesRawMean() {
        var summary = InventoryAggregationPolicy.summarizeConfirmedCounts(List.of(10, 11, 13));
        assertEquals(new BigDecimal("11.3333"), summary.rawMean());
        assertEquals(11, summary.roundedCount());
        assertEquals(3, summary.includedDays());
    }

    @Test
    void emptyInputHasNoSyntheticCount() {
        var summary = InventoryAggregationPolicy.summarizeConfirmedCounts(List.of());
        assertNull(summary.rawMean());
        assertNull(summary.roundedCount());
        assertEquals(0, summary.includedDays());
    }
}

