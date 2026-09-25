package com.smartfarm.inventory.capture.domain;

import java.math.BigDecimal;
import java.util.List;
import java.util.Objects;

/**
 * 栏舍在单张图像上的归属规则：有效区 + 不计入本栏的排除区 + 最小包含比例。
 *
 * <p>有效区与排除区使用 EXIF 纠正后的归一化坐标。排除区用于标记邻栏、料槽、走道等区域，
 * 检测框中心落在任一排除区内时不计入本栏（对应现场需求"隔壁栏舍的猪不能计入本栏舍"）。
 * {@code minContainment} 大于 0 时，检测框落在有效区内的面积占比必须达到该阈值才计入，
 * 用于排除半身在邻栏的目标；缺省 0 表示沿用"只判定框中心点"的历史口径。
 *
 * <p>不提供排除区与阈值的调用方可以继续使用四参数构造器，语义与既往完全一致。
 */
public record Roi(
        BigDecimal x,
        BigDecimal y,
        BigDecimal width,
        BigDecimal height,
        List<RoiRegion> exclusions,
        BigDecimal minContainment) {

    private static final BigDecimal ZERO = BigDecimal.ZERO;
    private static final BigDecimal ONE = BigDecimal.ONE;
    public static final int MAX_EXCLUSIONS = 8;

    public Roi {
        if (x == null || y == null || width == null || height == null) {
            throw new IllegalArgumentException("ROI coordinates are required when ROI is present");
        }
        if (x.compareTo(ZERO) < 0 || y.compareTo(ZERO) < 0 || width.compareTo(ZERO) <= 0
                || height.compareTo(ZERO) <= 0 || x.add(width).compareTo(ONE) > 0
                || y.add(height).compareTo(ONE) > 0) {
            throw new IllegalArgumentException("ROI must remain inside normalized image bounds");
        }
        // 注意：不可变集合的 contains(null) 会抛 NullPointerException，因此显式逐个判空。
        if (exclusions != null && exclusions.stream().anyMatch(Objects::isNull)) {
            throw new IllegalArgumentException("ROI exclusion regions must not be null");
        }
        exclusions = exclusions == null ? List.of() : List.copyOf(exclusions);
        if (exclusions.size() > MAX_EXCLUSIONS) {
            throw new IllegalArgumentException(
                    "ROI must not declare more than " + MAX_EXCLUSIONS + " exclusion regions");
        }
        minContainment = minContainment == null ? ZERO : minContainment;
        if (minContainment.compareTo(ZERO) < 0 || minContainment.compareTo(ONE) > 0) {
            throw new IllegalArgumentException("ROI minimum containment must be within 0..1");
        }
    }

    /** 只声明有效区的历史形式：按框中心点判定归属。 */
    public Roi(BigDecimal x, BigDecimal y, BigDecimal width, BigDecimal height) {
        this(x, y, width, height, List.of(), ZERO);
    }
}
