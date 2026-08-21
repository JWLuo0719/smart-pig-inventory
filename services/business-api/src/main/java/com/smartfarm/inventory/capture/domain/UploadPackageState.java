package com.smartfarm.inventory.capture.domain;

public enum UploadPackageState {
    AWAITING_BLOBS("awaiting_blobs"),
    AWAITING_MANIFEST("awaiting_manifest"),
    READY_TO_COMMIT("ready_to_commit"),
    COMMITTED("committed");

    private final String databaseValue;

    UploadPackageState(String databaseValue) {
        this.databaseValue = databaseValue;
    }

    public String databaseValue() {
        return databaseValue;
    }

    public static UploadPackageState fromDatabase(String value) {
        for (UploadPackageState state : values()) {
            if (state.databaseValue.equals(value)) {
                return state;
            }
        }
        throw new IllegalArgumentException("Unknown upload package state: " + value);
    }
}
