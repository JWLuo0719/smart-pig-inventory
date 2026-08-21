package com.smartfarm.inventory.capture.domain;

import java.math.BigDecimal;

public record Roi(BigDecimal x, BigDecimal y, BigDecimal width, BigDecimal height) {
    private static final BigDecimal ZERO = BigDecimal.ZERO;
    private static final BigDecimal ONE = BigDecimal.ONE;

    public Roi {
        if (x == null || y == null || width == null || height == null) {
            throw new IllegalArgumentException("ROI coordinates are required when ROI is present");
        }
        if (x.compareTo(ZERO) < 0 || y.compareTo(ZERO) < 0 || width.compareTo(ZERO) <= 0
                || height.compareTo(ZERO) <= 0 || x.add(width).compareTo(ONE) > 0
                || y.add(height).compareTo(ONE) > 0) {
            throw new IllegalArgumentException("ROI must remain inside normalized image bounds");
        }
    }
}
