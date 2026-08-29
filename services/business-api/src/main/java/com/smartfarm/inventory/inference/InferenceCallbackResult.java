package com.smartfarm.inventory.inference;

import jakarta.validation.Valid;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import java.util.List;
import java.util.UUID;

/** The internal, versioned result callback. Spring remains the business authority. */
public record InferenceCallbackResult(
        @NotBlank String status,
        @Min(0) Integer count,
        @NotNull List<@Valid Detection> detections,
        @NotNull List<@NotBlank String> warnings,
        @NotBlank String modelKey,
        @NotBlank String modelVersion,
        @NotBlank String modelChecksum,
        @NotBlank String adapterVersion,
        @NotBlank String inferenceSource,
        @Min(0) long latencyMs,
        String failureCode,
        String failureMessage) {
    public record Detection(
            @NotNull UUID assetId,
            @NotNull List<@NotNull Double> bbox,
            @Min(0) @Max(1) double confidence,
            int classId) {
        public Detection {
            if (bbox.size() != 4) {
                throw new IllegalArgumentException("A detection bounding box must contain four values");
            }
        }
    }

    public boolean isSucceeded() {
        return "succeeded".equals(status);
    }

    public boolean isReviewRequired() {
        return "review_required".equals(status);
    }

    public boolean isFailed() {
        return "failed".equals(status);
    }

    public InferenceCallbackResult requireManualReview(String warning) {
        java.util.ArrayList<String> normalizedWarnings = new java.util.ArrayList<>(warnings);
        normalizedWarnings.add(warning);
        return new InferenceCallbackResult(
                "review_required", null, detections, List.copyOf(normalizedWarnings), modelKey, modelVersion,
                modelChecksum, adapterVersion, inferenceSource, latencyMs, failureCode, failureMessage);
    }
}
