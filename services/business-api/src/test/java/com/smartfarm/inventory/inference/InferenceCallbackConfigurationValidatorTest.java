package com.smartfarm.inventory.inference;

import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import org.junit.jupiter.api.Test;

class InferenceCallbackConfigurationValidatorTest {
    @Test
    void rejectsAnEnabledDispatcherWithoutCallbackCredential() {
        InferenceCallbackConfigurationValidator validator =
                new InferenceCallbackConfigurationValidator(true, "");

        assertThatThrownBy(validator::requireCallbackCredentialWhenDispatching)
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("INFERENCE_CALLBACK_TOKEN");
    }

    @Test
    void allowsDisabledDispatcherOrAConfiguredCredential() {
        assertThatCode(() -> new InferenceCallbackConfigurationValidator(false, "")
                .requireCallbackCredentialWhenDispatching()).doesNotThrowAnyException();
        assertThatCode(() -> new InferenceCallbackConfigurationValidator(true, "local-e2e-secret")
                .requireCallbackCredentialWhenDispatching()).doesNotThrowAnyException();
    }
}
