package com.smartfarm.inventory.capture.domain;

import java.util.EnumSet;
import java.util.Set;

public final class CaptureSetPolicy {
    private CaptureSetPolicy() {
    }

    public static void validate(CaptureKind kind, Set<ViewPosition> positions) {
        if (kind == null || positions == null) {
            throw new IllegalArgumentException("Capture kind and positions are required");
        }
        Set<ViewPosition> actual = positions.isEmpty()
                ? EnumSet.noneOf(ViewPosition.class)
                : EnumSet.copyOf(positions);
        Set<ViewPosition> expected = switch (kind) {
            case SINGLE -> EnumSet.of(ViewPosition.SINGLE);
            case LEFT_CENTER_RIGHT -> EnumSet.of(ViewPosition.LEFT, ViewPosition.CENTER, ViewPosition.RIGHT);
            case VIDEO -> EnumSet.of(ViewPosition.VIDEO);
        };
        if (!actual.equals(expected)) {
            throw new IllegalArgumentException("Expected views " + expected + " but received " + actual);
        }
    }

    /**
     * 是否需要把推理结果强制降级为人工复核。
     *
     * <p>三视图与视频都必须先有"经验证的 Provider"（模型批准 + 现场标定）才能形成自动候选值；
     * 单图不受这两个开关影响。视频与三图的开关彼此独立：关闭视频计数不会影响三图判定。
     */
    public static boolean requiresManualReview(
            CaptureKind kind, boolean validatedMultiViewProvider, boolean validatedVideoProvider) {
        if (kind == null) {
            return true;
        }
        return switch (kind) {
            case SINGLE -> false;
            case LEFT_CENTER_RIGHT -> !validatedMultiViewProvider;
            case VIDEO -> !validatedVideoProvider;
        };
    }

    /**
     * 线上采集类型字符串版本，供结果回调按数据库中的 {@code capture_kind} 判定。
     *
     * <p>未知取值一律要求人工复核（失败关闭），不会因为枚举扩展或脏数据而放行自动数量。
     */
    public static boolean requiresManualReview(
            String wireCaptureKind, boolean validatedMultiViewProvider, boolean validatedVideoProvider) {
        if (wireCaptureKind == null) {
            return true;
        }
        return switch (wireCaptureKind) {
            case "single" -> requiresManualReview(CaptureKind.SINGLE, validatedMultiViewProvider, validatedVideoProvider);
            case "left_center_right" ->
                requiresManualReview(CaptureKind.LEFT_CENTER_RIGHT, validatedMultiViewProvider, validatedVideoProvider);
            case "video" -> requiresManualReview(CaptureKind.VIDEO, validatedMultiViewProvider, validatedVideoProvider);
            default -> true;
        };
    }
}
