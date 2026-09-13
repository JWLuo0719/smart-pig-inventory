package com.smartfarm.inventory.inference;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;
import static org.springframework.security.test.web.servlet.setup.SecurityMockMvcConfigurers.springSecurity;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.smartfarm.inventory.config.SecurityConfiguration;
import java.util.UUID;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.boot.test.context.runner.WebApplicationContextRunner;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Import;
import org.springframework.http.MediaType;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.web.servlet.config.annotation.EnableWebMvc;

/** Exercises the real MVC handler, problem response and security chain in both login modes. */
class InferenceCallbackSecurityTest {
    private static final String SERVICE_KEY = "synthetic-callback-test-only";
    private static final UUID JOB_ID = UUID.fromString("641bf993-ac8a-43d6-b9d2-e547c1fb2880");
    private static final String BODY = """
            {"status":"review_required","count":null,"detections":[],"warnings":[],
             "modelKey":"test-model","modelVersion":"test-version","modelChecksum":"unverified",
             "adapterVersion":"http-v1","inferenceSource":"unavailable","latencyMs":0}
            """;

    @ParameterizedTest
    @ValueSource(booleans = {false, true})
    void rejectsMissingBlankAndWrongKeysBeforeCallingTheBusinessService(boolean securityEnabled) {
        context(securityEnabled, SERVICE_KEY).run(context -> {
            assertThat(context).hasNotFailed();
            MockMvc mvc = MockMvcBuilders.webAppContextSetup(context).apply(springSecurity()).build();
            for (String supplied : new String[] {null, "", " ", "wrong-key", SERVICE_KEY.toUpperCase(), SERVICE_KEY + "-extra"}) {
                var response = mvc.perform(request(supplied))
                        .andExpect(status().isUnauthorized())
                        .andExpect(jsonPath("code").value("INFERENCE_CALLBACK_UNAUTHORIZED"))
                        .andReturn().getResponse();
                assertThat(response.getContentAsString()).doesNotContain(SERVICE_KEY, "wrong-key");
            }
            verifyNoInteractions(context.getBean(InferenceResultService.class));
        });
    }

    @ParameterizedTest
    @ValueSource(booleans = {false, true})
    void acceptsExactServiceKeyWithoutUserJwtAndPreservesReplayStatus(boolean securityEnabled) {
        context(securityEnabled, SERVICE_KEY).run(context -> {
            assertThat(context).hasNotFailed();
            MockMvc mvc = MockMvcBuilders.webAppContextSetup(context).apply(springSecurity()).build();
            var service = context.getBean(InferenceResultService.class);
            when(service.accept(eq(JOB_ID), any())).thenReturn(
                    InferenceResultService.CallbackOutcome.CREATED, InferenceResultService.CallbackOutcome.REPLAYED);
            mvc.perform(request(SERVICE_KEY)).andExpect(status().isNoContent());
            mvc.perform(request(SERVICE_KEY)).andExpect(status().isOk());
            verify(service, times(2)).accept(eq(JOB_ID), any());
        });
    }

    @ParameterizedTest
    @ValueSource(booleans = {false, true})
    void anAuthenticatedAdministratorCannotSubstituteForTheServiceKey(boolean securityEnabled) {
        context(securityEnabled, SERVICE_KEY).run(context -> {
            MockMvc mvc = MockMvcBuilders.webAppContextSetup(context).apply(springSecurity()).build();
            mvc.perform(request(null).with(jwt().jwt(token -> token.subject("system-admin")
                            .claim("roles", java.util.List.of("SYSTEM_ADMIN")))))
                    .andExpect(status().isUnauthorized())
                    .andExpect(jsonPath("code").value("INFERENCE_CALLBACK_UNAUTHORIZED"));
            verifyNoInteractions(context.getBean(InferenceResultService.class));
        });
    }

    @ParameterizedTest
    @ValueSource(booleans = {false, true})
    void anUnconfiguredOrWhitespaceOnlyServerKeyNeverAcceptsCallbacks(boolean securityEnabled) {
        for (String configured : new String[] {"", "   "}) {
            context(securityEnabled, configured).run(context -> {
                assertThat(context).hasNotFailed();
                MockMvc mvc = MockMvcBuilders.webAppContextSetup(context).apply(springSecurity()).build();
                mvc.perform(request(configured)).andExpect(status().isUnauthorized());
                mvc.perform(request(SERVICE_KEY)).andExpect(status().isUnauthorized());
                verifyNoInteractions(context.getBean(InferenceResultService.class));
            });
        }
    }

    private WebApplicationContextRunner context(boolean securityEnabled, String configuredKey) {
        return new WebApplicationContextRunner().withUserConfiguration(TestWebConfiguration.class)
                .withPropertyValues("app.security.enabled=" + securityEnabled,
                        "app.inference.callback-token=" + configuredKey);
    }

    private MockHttpServletRequestBuilder request(String key) {
        var request = put("/api/v1/inference-jobs/{jobId}/result", JOB_ID)
                .header("X-Idempotency-Key", JOB_ID).contentType(MediaType.APPLICATION_JSON).content(BODY);
        return key == null ? request : request.header("X-Inference-Service-Key", key);
    }

    @Configuration(proxyBeanMethods = false)
    @EnableWebMvc
    @EnableWebSecurity
    @Import({SecurityConfiguration.class, InferenceCallbackAuthenticator.class,
            InferenceResultController.class, InferenceProblemHandler.class})
    static class TestWebConfiguration {
        @Bean InferenceResultService inferenceResultService() { return mock(InferenceResultService.class); }
        @Bean JwtDecoder jwtDecoder() { return mock(JwtDecoder.class); }
    }
}
