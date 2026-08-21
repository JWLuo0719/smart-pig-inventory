package com.smartfarm.inventory.capture.domain;

public enum CaptureKind {
    SINGLE,
    LEFT_CENTER_RIGHT,
    VIDEO;

    public static CaptureKind fromWire(String value) {
        return switch (value) {
            case "single" -> SINGLE;
            case "left_center_right" -> LEFT_CENTER_RIGHT;
            default -> throw new IllegalArgumentException("Unsupported capture kind: " + value);
        };
    }

    public String wireValue() {
        return switch (this) {
            case SINGLE -> "single";
            case LEFT_CENTER_RIGHT -> "left_center_right";
            case VIDEO -> "video";
        };
    }
}

