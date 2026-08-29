package com.smartfarm.inventory.capture.domain;

import java.time.Instant;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

public record ManifestAsset(
        UUID assetId,
        ViewPosition viewPosition,
        Instant capturedAt,
        String originalName,
        int width,
        int height,
        String sha256,
        String perceptualHash,
        long byteSize,
        String mediaType,
        Map<String, Object> exif,
        Roi roi) {

    public ManifestAsset {
        if (assetId == null || viewPosition == null || capturedAt == null || originalName == null || originalName.isBlank()
                || sha256 == null || !sha256.matches("^[a-f0-9]{64}$") || mediaType == null || exif == null) {
            throw new IllegalArgumentException("Manifest asset contains required invalid fields");
        }
        if (width <= 0 || height <= 0 || byteSize <= 0) {
            throw new IllegalArgumentException("Manifest asset dimensions and byte size must be positive");
        }
        if (!mediaType.equals("image/jpeg") && !mediaType.equals("image/png") && !mediaType.equals("image/heic")) {
            throw new IllegalArgumentException("Unsupported image media type");
        }
        if (originalName.length() > 255) {
            throw new IllegalArgumentException("Original name is too long");
        }
        if (perceptualHash != null && !perceptualHash.matches("^[a-f0-9]{16}$")) {
            throw new IllegalArgumentException("Perceptual hash must be a 64-bit lowercase hexadecimal value");
        }
        Set<String> permittedExifFields = Set.of(
                "orientation", "make", "model", "focalLengthMm", "exposureTimeSeconds", "iso");
        if (!permittedExifFields.containsAll(exif.keySet())) {
            throw new IllegalArgumentException("Manifest EXIF contains a field not permitted by the contract");
        }
    }
}
