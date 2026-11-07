package com.smartfarm.inventory.system;

import java.time.Duration;
import java.util.Map;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;

/** The asynchronous inference service owns runtime readiness; configuration alone proves nothing. */
@Component
public class InferenceCapabilities {
    private final RestClient client;
    private final String provider;
    private final Map<String, String> identity;

    @Autowired
    public InferenceCapabilities(
            @Value("${app.inference.base-url}") String baseUrl,
            @Value("${app.inference.provider:unavailable}") String provider,
            @Value("${app.inference.model-key}") String key,
            @Value("${app.inference.model-version}") String version,
            @Value("${app.inference.model-checksum}") String checksum,
            @Value("${app.inference.adapter-version}") String adapter) {
        this(clientBuilder(baseUrl), provider, Map.of("model_key", key, "model_version", version,
                "model_checksum", checksum, "adapter_version", adapter));
    }

    InferenceCapabilities(RestClient.Builder builder, String provider, Map<String, String> identity) {
        this.client = builder.build();
        this.provider = provider;
        this.identity = Map.copyOf(identity);
    }

    private static RestClient.Builder clientBuilder(String baseUrl) {
        var factory = new SimpleClientHttpRequestFactory();
        factory.setConnectTimeout(Duration.ofSeconds(2));
        factory.setReadTimeout(Duration.ofSeconds(2));
        return RestClient.builder().baseUrl(baseUrl).requestFactory(factory);
    }

    public Map<String, Object> snapshot() {
        if (!"research-http-yolo".equals(provider) && !"http-yolo".equals(provider)) {
            return unavailable("NO_VALIDATED_PROVIDER");
        }
        try {
            Map<?, ?> ready = client.get().uri("/health/ready").retrieve().body(Map.class);
            if (ready == null || !Boolean.TRUE.equals(ready.get("ready"))
                    || !Boolean.TRUE.equals(ready.get("counting_available"))) {
                return unavailable("RUNNER_NOT_READY");
            }
            if (!provider.equals(ready.get("provider"))
                    || identity.entrySet().stream().anyMatch(e -> !e.getValue().equals(ready.get(e.getKey())))) {
                return unavailable("RUNNER_IDENTITY_MISMATCH");
            }
            return Map.of("counting_provider", provider, "counting_available", true,
                    "detection_available", true, "automatic_counting", false,
                    "manual_review_required", true, "reason_code", "MANUAL_REVIEW_REQUIRED");
        } catch (RuntimeException exception) {
            return unavailable("RUNNER_UNAVAILABLE");
        }
    }

    private Map<String, Object> unavailable(String reason) {
        return Map.of("counting_provider", provider, "counting_available", false,
                "detection_available", false, "automatic_counting", false,
                "manual_review_required", true, "reason_code", reason);
    }
}
