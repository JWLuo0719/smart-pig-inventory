package com.smartfarm.inventory.capture.domain;

import java.util.List;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;

public record CaptureManifest(UUID captureSetId, CaptureKind captureKind, UUID penId, List<ManifestAsset> assets) {
    public CaptureManifest {
        if (captureSetId == null || captureKind == null || penId == null || assets == null || assets.isEmpty()) {
            throw new IllegalArgumentException("Capture manifest requires set, kind, pen and assets");
        }
        int expectedSize = captureKind == CaptureKind.LEFT_CENTER_RIGHT ? 3 : 1;
        if (assets.size() != expectedSize) {
            throw new IllegalArgumentException("Capture manifest must contain exactly the required views");
        }
        Set<UUID> assetIds = assets.stream().map(ManifestAsset::assetId).collect(Collectors.toSet());
        if (assetIds.size() != assets.size()) {
            throw new IllegalArgumentException("Manifest cannot repeat an asset ID");
        }
        CaptureSetPolicy.validate(captureKind, assets.stream()
                .map(ManifestAsset::viewPosition)
                .collect(Collectors.toSet()));
    }
}
