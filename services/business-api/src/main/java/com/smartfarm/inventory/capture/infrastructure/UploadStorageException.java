package com.smartfarm.inventory.capture.infrastructure;

public class UploadStorageException extends RuntimeException {
    private UploadStorageException(String message, Throwable cause) {
        super(message, cause);
    }

    static UploadStorageException writeFailed(Throwable cause) {
        return new UploadStorageException("Evidence object storage operation failed", cause);
    }
}
