package com.smartfarm.inventory.capture.domain;

import static org.junit.jupiter.api.Assertions.assertDoesNotThrow;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.util.EnumSet;
import org.junit.jupiter.api.Test;

class CaptureSetPolicyTest {
    @Test
    void acceptsCompleteLeftCenterRightSet() {
        assertDoesNotThrow(() -> CaptureSetPolicy.validate(
                CaptureKind.LEFT_CENTER_RIGHT,
                EnumSet.of(ViewPosition.LEFT, ViewPosition.CENTER, ViewPosition.RIGHT)));
    }

    @Test
    void rejectsIncompleteLeftCenterRightSet() {
        assertThrows(IllegalArgumentException.class, () -> CaptureSetPolicy.validate(
                CaptureKind.LEFT_CENTER_RIGHT,
                EnumSet.of(ViewPosition.LEFT, ViewPosition.CENTER)));
    }

    @Test
    void multiViewRequiresReviewWithoutValidatedProvider() {
        assertTrue(CaptureSetPolicy.requiresManualReview(CaptureKind.LEFT_CENTER_RIGHT, false));
    }
}

