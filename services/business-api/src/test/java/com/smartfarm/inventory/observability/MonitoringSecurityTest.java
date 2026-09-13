package com.smartfarm.inventory.observability;

import static org.springframework.security.test.web.servlet.setup.SecurityMockMvcConfigurers.springSecurity;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;
import static org.mockito.Mockito.mock;
import com.smartfarm.inventory.config.SecurityConfiguration;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.boot.test.context.runner.WebApplicationContextRunner;
import org.springframework.context.annotation.*;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.servlet.config.annotation.EnableWebMvc;

class MonitoringSecurityTest {
    @ParameterizedTest @ValueSource(booleans = {false, true})
    void onlyTheIndependentKeyCanReadGlobalMetrics(boolean userSecurity) {
        context(userSecurity, "synthetic-monitor-key").run(context -> {
            var mvc = MockMvcBuilders.webAppContextSetup(context).apply(springSecurity()).build();
            for (String path : new String[] {"/actuator/prometheus", "/actuator/metrics", "/actuator/metrics/pig.inventory.review.pending"}) {
                mvc.perform(get(path)).andExpect(status().isUnauthorized());
                mvc.perform(get(path).header("X-Monitoring-Service-Key", "wrong")).andExpect(status().isUnauthorized());
                mvc.perform(get(path).with(jwt().jwt(token -> token.subject("system-admin")))).andExpect(status().isUnauthorized());
                mvc.perform(get(path).header("X-Monitoring-Service-Key", "synthetic-monitor-key")).andExpect(status().isOk());
            }
            mvc.perform(get("/actuator/health")).andExpect(status().isOk());
        });
    }
    @ParameterizedTest @ValueSource(booleans = {false, true})
    void blankConfigurationIsFailClosed(boolean userSecurity) {
        context(userSecurity, " ").run(context -> {
            var mvc = MockMvcBuilders.webAppContextSetup(context).apply(springSecurity()).build();
            mvc.perform(get("/actuator/prometheus").header("X-Monitoring-Service-Key", " ")).andExpect(status().isUnauthorized());
        });
    }
    private WebApplicationContextRunner context(boolean enabled, String key) {
        return new WebApplicationContextRunner().withUserConfiguration(TestConfiguration.class)
                .withPropertyValues("app.security.enabled=" + enabled, "app.monitoring.service-key=" + key);
    }
    @Configuration @EnableWebMvc @EnableWebSecurity
    @Import({SecurityConfiguration.class, MonitoringSecurityConfiguration.class, Endpoints.class})
    static class TestConfiguration { @Bean JwtDecoder decoder() { return mock(JwtDecoder.class); } }
    @RestController static class Endpoints {
        @GetMapping({"/actuator/prometheus", "/actuator/metrics", "/actuator/metrics/{name}", "/actuator/health"})
        String ok() { return "synthetic"; }
    }
}
