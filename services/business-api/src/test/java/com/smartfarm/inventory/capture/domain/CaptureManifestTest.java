package com.smartfarm.inventory.capture.domain;

import static org.junit.jupiter.api.Assertions.assertDoesNotThrow;
import static org.junit.jupiter.api.Assertions.assertThrows;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.Test;

class CaptureManifestTest {
    @Test
    void acceptsThreeDistinctViewsAndBoundaryRoi() {
        assertDoesNotThrow(() -> new CaptureManifest(
                UUID.randomUUID(),
                CaptureKind.LEFT_CENTER_RIGHT,
                UUID.randomUUID(),
                List.of(asset(ViewPosition.LEFT), asset(ViewPosition.CENTER), asset(ViewPosition.RIGHT))));
        assertDoesNotThrow(() -> new Roi(BigDecimal.ZERO, BigDecimal.ZERO, BigDecimal.ONE, BigDecimal.ONE));
    }

    @Test
    void rejectsInvalidPerceptualHash() {
        assertThrows(IllegalArgumentException.class, () -> new ManifestAsset(
                UUID.randomUUID(), ViewPosition.SINGLE, Instant.parse("2026-08-20T01:00:00Z"), "single.jpg", 100, 100,
                "a".repeat(64), "not-a-perceptual-hash", 10, "image/jpeg", Map.of(), null));
    }

    @Test
    void rejectsDuplicateDirectionAndOutOfBoundsRoi() {
        assertThrows(IllegalArgumentException.class, () -> new CaptureManifest(
                UUID.randomUUID(),
                CaptureKind.LEFT_CENTER_RIGHT,
                UUID.randomUUID(),
                List.of(asset(ViewPosition.LEFT), asset(ViewPosition.LEFT), asset(ViewPosition.RIGHT))));
        assertThrows(IllegalArgumentException.class,
                () -> new Roi(new BigDecimal("0.8"), BigDecimal.ZERO, new BigDecimal("0.3"), BigDecimal.ONE));
    }

    private ManifestAsset asset(ViewPosition position) {
        return new ManifestAsset(
                UUID.randomUUID(),
                position,
                Instant.parse("2026-08-20T01:00:00Z"),
                position.name().toLowerCase() + ".jpg",
                1920,
                1080,
                "a".repeat(64),
                null,
                10,
                "image/jpeg",
                Map.of(),
                null);
    }
}
