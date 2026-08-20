package com.smartfarm.inventory.inventory.domain;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.List;

public final class InventoryAggregationPolicy {
    private InventoryAggregationPolicy() {
    }

    public static InventorySummary summarizeConfirmedCounts(List<Integer> confirmedCounts) {
        if (confirmedCounts == null || confirmedCounts.isEmpty()) {
            return new InventorySummary(null, null, 0);
        }
        if (confirmedCounts.stream().anyMatch(value -> value == null || value < 0)) {
            throw new IllegalArgumentException("Confirmed counts must be non-negative integers");
        }
        BigDecimal sum = confirmedCounts.stream()
                .map(BigDecimal::valueOf)
                .reduce(BigDecimal.ZERO, BigDecimal::add);
        BigDecimal mean = sum.divide(BigDecimal.valueOf(confirmedCounts.size()), 4, RoundingMode.HALF_UP);
        return new InventorySummary(mean, mean.setScale(0, RoundingMode.HALF_UP).intValueExact(), confirmedCounts.size());
    }

    public record InventorySummary(BigDecimal rawMean, Integer roundedCount, int includedDays) {
    }
}

