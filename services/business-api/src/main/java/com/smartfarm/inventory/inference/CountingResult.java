package com.smartfarm.inventory.inference;

import com.fasterxml.jackson.databind.PropertyNamingStrategies;
import com.fasterxml.jackson.databind.annotation.JsonNaming;
import java.util.List;
import java.util.Map;

@JsonNaming(PropertyNamingStrategies.SnakeCaseStrategy.class)
public record CountingResult(
        Status status,
        Integer count,
        List<Map<String, Object>> detections,
        List<String> warnings,
        String modelKey,
        String modelVersion,
        String modelChecksum,
        String adapterVersion,
        String inferenceSource,
        long latencyMs) {
    public enum Status {
        SUCCEEDED,
        REVIEW_REQUIRED,
        FAILED
    }
}
