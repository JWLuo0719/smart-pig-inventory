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

    public static boolean requiresManualReview(CaptureKind kind, boolean validatedMultiViewProvider) {
        return kind == CaptureKind.LEFT_CENTER_RIGHT && !validatedMultiViewProvider;
    }
}

