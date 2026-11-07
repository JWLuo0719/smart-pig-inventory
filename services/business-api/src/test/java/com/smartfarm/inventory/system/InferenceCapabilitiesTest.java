package com.smartfarm.inventory.system;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.requestTo;
import static org.springframework.test.web.client.response.MockRestResponseCreators.*;

import java.util.Map;
import org.junit.jupiter.api.Test;
import org.springframework.http.MediaType;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.web.client.RestClient;

class InferenceCapabilitiesTest {
    private final RestClient.Builder builder = RestClient.builder().baseUrl("http://inference.invalid");
    private final MockRestServiceServer server = MockRestServiceServer.bindTo(builder).build();
    private final Map<String, String> identity = Map.of("model_key", "pig", "model_version", "v1",
            "model_checksum", "checksum", "adapter_version", "http-v1");

    @Test
    void researchReadinessProvidesCandidatesAndAlwaysRequiresReview() {
        server.expect(requestTo("http://inference.invalid/health/ready")).andRespond(withSuccess("""
                {"ready":true,"counting_available":true,"provider":"research-http-yolo",
                 "model_key":"pig","model_version":"v1","model_checksum":"checksum","adapter_version":"http-v1"}
                """, MediaType.APPLICATION_JSON));
        var result = new InferenceCapabilities(builder, "research-http-yolo", identity).snapshot();
        assertThat(result).containsEntry("counting_available", true).containsEntry("automatic_counting", false)
                .containsEntry("manual_review_required", true);
        server.verify();
    }

    @Test
    void changedModelFailsClosed() {
        server.expect(requestTo("http://inference.invalid/health/ready")).andRespond(withSuccess("""
                {"ready":true,"counting_available":true,"provider":"research-http-yolo",
                 "model_key":"pig","model_version":"v2","model_checksum":"checksum","adapter_version":"http-v1"}
                """, MediaType.APPLICATION_JSON));
        assertThat(new InferenceCapabilities(builder, "research-http-yolo", identity).snapshot())
                .containsEntry("detection_available", false).containsEntry("reason_code", "RUNNER_IDENTITY_MISMATCH");
    }

    @Test
    void failedOrMalformedReadinessExposesNoInternalDetails() {
        server.expect(requestTo("http://inference.invalid/health/ready")).andRespond(withServerError());
        assertThat(new InferenceCapabilities(builder, "research-http-yolo", identity).snapshot())
                .containsEntry("counting_available", false).containsEntry("reason_code", "RUNNER_UNAVAILABLE");
    }

    @Test
    void unconfiguredProviderNeedsNoNetwork() {
        assertThat(new InferenceCapabilities(builder, "unavailable", identity).snapshot())
                .containsEntry("counting_available", false).containsEntry("reason_code", "NO_VALIDATED_PROVIDER");
        server.verify();
    }
}
