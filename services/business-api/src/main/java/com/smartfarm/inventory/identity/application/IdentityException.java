package com.smartfarm.inventory.identity.application;

public class IdentityException extends RuntimeException {
    private final int status;
    private final String code;

    private IdentityException(int status, String code, String message) {
        super(message);
        this.status = status;
        this.code = code;
    }

    public static IdentityException unauthorized(String code) {
        return new IdentityException(401, code, "Authentication failed");
    }

    public static IdentityException conflict(String code) {
        return new IdentityException(409, code, "Authentication request conflicts with current session state");
    }

    public int status() {
        return status;
    }

    public String code() {
        return code;
    }
}
