package com.smartfarm.inventory.capture.domain;

public enum ViewPosition {
    SINGLE,
    LEFT,
    CENTER,
    RIGHT,
    VIDEO;

    public static ViewPosition fromWire(String value) {
        return switch (value) {
            case "single" -> SINGLE;
            case "left" -> LEFT;
            case "center" -> CENTER;
            case "right" -> RIGHT;
            default -> throw new IllegalArgumentException("Unsupported view position: " + value);
        };
    }

    public String wireValue() {
        return name().toLowerCase(java.util.Locale.ROOT);
    }
}

