package com.smartfarm.inventory.inference;

import jakarta.annotation.PostConstruct;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

/** Fails closed instead of dispatching jobs that can never authenticate their terminal callback. */
@Component
public class InferenceCallbackConfigurationValidator {
    private final boolean dispatcherEnabled;
    private final String callbackToken;

    public InferenceCallbackConfigurationValidator(
            @Value("${app.inference.dispatcher.enabled:false}") boolean dispatcherEnabled,
            @Value("${app.inference.callback-token:}") String callbackToken) {
        this.dispatcherEnabled = dispatcherEnabled;
        this.callbackToken = callbackToken;
    }

    @PostConstruct
    void requireCallbackCredentialWhenDispatching() {
        if (dispatcherEnabled && callbackToken.isBlank()) {
            throw new IllegalStateException(
                    "INFERENCE_CALLBACK_TOKEN must be configured when the inference dispatcher is enabled");
        }
    }
}
