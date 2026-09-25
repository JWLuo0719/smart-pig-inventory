package com.smartfarm.inventory.capture.domain;

import java.math.BigDecimal;

/**
 * 归一化矩形区域，用于栏舍有效区或"不计入本栏"的排除区。
 *
 * <p>坐标基于 EXIF 纠正后的图像，取值 0..1，且必须完整落在图像内。
 */
public record RoiRegion(BigDecimal x, BigDecimal y, BigDecimal width, BigDecimal height) {
    private static final BigDecimal ZERO = BigDecimal.ZERO;
    private static final BigDecimal ONE = BigDecimal.ONE;

    public RoiRegion {
        if (x == null || y == null || width == null || height == null) {
            throw new IllegalArgumentException("ROI region coordinates are required when a region is present");
        }
        if (x.compareTo(ZERO) < 0 || y.compareTo(ZERO) < 0 || width.compareTo(ZERO) <= 0
                || height.compareTo(ZERO) <= 0 || x.add(width).compareTo(ONE) > 0
                || y.add(height).compareTo(ONE) > 0) {
            throw new IllegalArgumentException("ROI region must remain inside normalized image bounds");
        }
    }
}
