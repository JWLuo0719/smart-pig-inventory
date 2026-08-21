package com.smartfarm.inventory.capture.application;

import java.util.UUID;

public record CommitUploadResult(UUID packageId, UUID sessionId, UUID inferenceJobId, String status) {
}
