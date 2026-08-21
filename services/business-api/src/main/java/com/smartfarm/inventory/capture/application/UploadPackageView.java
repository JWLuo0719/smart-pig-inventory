package com.smartfarm.inventory.capture.application;

import com.smartfarm.inventory.capture.domain.UploadPackageState;
import java.util.List;
import java.util.UUID;

public record UploadPackageView(UUID id, UUID clientPackageId, UploadPackageState state, List<UUID> existingAssets) {
}
