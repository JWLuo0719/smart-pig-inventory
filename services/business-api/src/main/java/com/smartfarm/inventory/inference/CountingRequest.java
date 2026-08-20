package com.smartfarm.inventory.inference;

import com.fasterxml.jackson.databind.PropertyNamingStrategies;
import com.fasterxml.jackson.databind.annotation.JsonNaming;
import java.util.List;
import java.util.Map;
import java.util.UUID;

@JsonNaming(PropertyNamingStrategies.SnakeCaseStrategy.class)
public record CountingRequest(
        UUID jobId,
        String correlationId,
        UUID organizationId,
        UUID captureSetId,
        String captureKind,
        List<MediaReference> media,
        ModelIdentity requestedModel) {
    @JsonNaming(PropertyNamingStrategies.SnakeCaseStrategy.class)
    public record MediaReference(
            UUID assetId,
            String viewPosition,
            String objectUri,
            String sha256,
            Map<String, Object> roi) {
    }

    @JsonNaming(PropertyNamingStrategies.SnakeCaseStrategy.class)
    public record ModelIdentity(String modelKey, String version, String checksum, String adapterVersion) {
    }
}
