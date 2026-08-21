package com.smartfarm.inventory.capture.application;

import com.smartfarm.inventory.capture.domain.CaptureKind;
import java.time.LocalDate;
import java.util.UUID;

public record UploadCommand(UUID clientPackageId, UUID organizationId, UUID penId, LocalDate businessDate, CaptureKind captureKind) {
}
