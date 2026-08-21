package com.smartfarm.inventory.capture.application;

public class UploadException extends RuntimeException {
    private final int status;
    private final String code;

    private UploadException(int status, String code, String message) {
        super(message);
        this.status = status;
        this.code = code;
    }

    public static UploadException conflict(String code, String message) {
        return new UploadException(409, code, message);
    }

    public static UploadException invalid(String code, String message) {
        return new UploadException(422, code, message);
    }

    public static UploadException notFound() {
        return new UploadException(404, "UPLOAD_PACKAGE_NOT_FOUND", "Upload package was not found");
    }

    public static UploadException forbidden(String message) {
        return new UploadException(403, "ORGANIZATION_ACCESS_DENIED", message);
    }

    public int status() {
        return status;
    }

    public String code() {
        return code;
    }
}
