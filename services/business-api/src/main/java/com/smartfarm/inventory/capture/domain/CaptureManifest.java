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
        if (captureKind == CaptureKind.VIDEO || assets.size() > 3) {
            throw new IllegalArgumentException("Capture manifest supports only one or three images");
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
