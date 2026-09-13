package com.smartfarm.inventory.capture.domain;

import static org.junit.jupiter.api.Assertions.*;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.Test;

class VideoEvidenceTest {
    private ManifestAsset asset(ViewPosition position, String type, long bytes) {
        return new ManifestAsset(UUID.randomUUID(), position, Instant.now(), "synthetic.mp4", 640, 480,
                "a".repeat(64), null, bytes, type, Map.of(), null);
    }
    @Test void acceptsOneVideoAndRequiresManualReviewRegardlessOfMultiViewFlag() {
        assertDoesNotThrow(() -> new CaptureManifest(UUID.randomUUID(), CaptureKind.fromWire("video"), UUID.randomUUID(),
                List.of(asset(ViewPosition.fromWire("video"), "video/mp4", 100))));
        assertTrue(CaptureSetPolicy.requiresManualReview(CaptureKind.VIDEO, true));
        assertTrue(CaptureSetPolicy.requiresManualReview(CaptureKind.VIDEO, false));
    }
    @Test void rejectsMixedMediaExtraViewsAndOversizedVideo() {
        assertThrows(IllegalArgumentException.class, () -> asset(ViewPosition.SINGLE, "video/mp4", 100));
        assertThrows(IllegalArgumentException.class, () -> asset(ViewPosition.VIDEO, "image/jpeg", 100));
        assertThrows(IllegalArgumentException.class, () -> asset(ViewPosition.VIDEO, "video/mp4", 30L * 1024 * 1024 + 1));
        assertThrows(IllegalArgumentException.class, () -> new CaptureManifest(UUID.randomUUID(), CaptureKind.VIDEO, UUID.randomUUID(),
                List.of(asset(ViewPosition.VIDEO, "video/mp4", 100), asset(ViewPosition.VIDEO, "video/mp4", 100))));
    }
}
