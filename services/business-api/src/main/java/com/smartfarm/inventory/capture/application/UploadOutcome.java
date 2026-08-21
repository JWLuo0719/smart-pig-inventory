package com.smartfarm.inventory.capture.application;

public record UploadOutcome<T>(T body, boolean replayed) {
    public int httpStatus() {
        return replayed ? 200 : 201;
    }
}
