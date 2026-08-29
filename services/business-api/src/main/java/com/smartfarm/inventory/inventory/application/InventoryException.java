package com.smartfarm.inventory.inventory.application;

public class InventoryException extends RuntimeException {
    private final int status;
    private final String code;

    private InventoryException(int status, String code, String message) {
        super(message);
        this.status = status;
        this.code = code;
    }

    public static InventoryException notFound() {
        return new InventoryException(404, "INVENTORY_NOT_FOUND", "The requested inventory evidence is not available");
    }

    public static InventoryException conflict(String message) {
        return new InventoryException(409, "INVENTORY_STATE_CONFLICT", message);
    }

    public static InventoryException invalid(String message) {
        return new InventoryException(422, "INVENTORY_VALIDATION_FAILED", message);
    }

    public int status() { return status; }

    public String code() { return code; }
}
