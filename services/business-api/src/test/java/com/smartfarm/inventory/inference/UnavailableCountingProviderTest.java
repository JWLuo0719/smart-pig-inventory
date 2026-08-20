package com.smartfarm.inventory.inference;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.Test;

class UnavailableCountingProviderTest {
    @Test
    void neverProducesAFakeCountAndPreservesRequestedModelIdentity() {
        CountingRequest.ModelIdentity model =
                new CountingRequest.ModelIdentity("pig-yolov13", "unverified", "0".repeat(64), "1");
        CountingRequest request = new CountingRequest(
                UUID.randomUUID(),
                "test-correlation",
                UUID.randomUUID(),
                UUID.randomUUID(),
                "single",
                List.of(new CountingRequest.MediaReference(
                        UUID.randomUUID(),
                        "single",
                        "s3://pig-inventory/photo.jpg",
                        "a".repeat(64),
                        Map.of())),
                model);

        CountingResult result = new UnavailableCountingProvider().count(request);

        assertThat(result.status()).isEqualTo(CountingResult.Status.REVIEW_REQUIRED);
        assertThat(result.count()).isNull();
        assertThat(result.detections()).isEmpty();
        assertThat(result.modelKey()).isEqualTo(model.modelKey());
        assertThat(result.inferenceSource()).isEqualTo("unavailable");
    }
}
