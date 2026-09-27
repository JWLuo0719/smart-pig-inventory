package com.smartfarm.inventory.capture.domain;

import static org.junit.jupiter.api.Assertions.assertDoesNotThrow;
import static org.junit.jupiter.api.Assertions.assertFalse;
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
        assertTrue(CaptureSetPolicy.requiresManualReview(CaptureKind.LEFT_CENTER_RIGHT, false, false));
    }

    @Test
    void multiViewStopsRequiringReviewOnceItsProviderIsValidated() {
        assertFalse(CaptureSetPolicy.requiresManualReview(CaptureKind.LEFT_CENTER_RIGHT, true, false));
    }

    @Test
    void videoRequiresReviewUntilItsOwnProviderIsValidated() {
        assertTrue(CaptureSetPolicy.requiresManualReview(CaptureKind.VIDEO, true, false));
        assertTrue(CaptureSetPolicy.requiresManualReview(CaptureKind.VIDEO, false, false));
        assertFalse(CaptureSetPolicy.requiresManualReview(CaptureKind.VIDEO, false, true));
    }

    @Test
    void singleImageIsNeverForcedIntoReview() {
        assertFalse(CaptureSetPolicy.requiresManualReview(CaptureKind.SINGLE, false, false));
    }

    @Test
    void wireCaptureKindDecisionsFailClosedForUnknownValues() {
        assertTrue(CaptureSetPolicy.requiresManualReview("mystery", false, false));
        assertTrue(CaptureSetPolicy.requiresManualReview((String) null, false, false));
        assertTrue(CaptureSetPolicy.requiresManualReview((CaptureKind) null, false, false));
        assertFalse(CaptureSetPolicy.requiresManualReview("single", false, false));
        assertFalse(CaptureSetPolicy.requiresManualReview("video", false, true));
        assertFalse(CaptureSetPolicy.requiresManualReview("left_center_right", true, false));
    }
}

