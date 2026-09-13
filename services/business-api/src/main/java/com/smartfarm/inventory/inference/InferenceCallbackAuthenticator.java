package com.smartfarm.inventory.inference;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

@Component
public class InferenceCallbackAuthenticator {
    private final String callbackToken;

    public InferenceCallbackAuthenticator(
            @Value("${app.inference.callback-token:}") String callbackToken) {
        this.callbackToken = callbackToken;
    }

    public void assertAuthorized(String suppliedToken) {
        // Service-to-service trust is independent of local end-user authentication.
        if (callbackToken.isBlank() || suppliedToken == null
                || !MessageDigest.isEqual(callbackToken.getBytes(StandardCharsets.UTF_8), suppliedToken.getBytes(StandardCharsets.UTF_8))) {
            throw InferenceException.unauthorized();
        }
    }
}
