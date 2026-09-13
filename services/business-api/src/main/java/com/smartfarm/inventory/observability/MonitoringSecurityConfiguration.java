package com.smartfarm.inventory.observability;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.annotation.Order;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.web.SecurityFilterChain;

/** Global operational aggregates are never authorized by an end-user organization JWT. */
@Configuration
public class MonitoringSecurityConfiguration {
    @Bean
    @Order(1)
    SecurityFilterChain monitoringSecurity(HttpSecurity http,
            @Value("${app.monitoring.service-key:}") String key) throws Exception {
        return http.securityMatcher("/actuator/prometheus", "/actuator/metrics", "/actuator/metrics/**")
                .csrf(csrf -> csrf.disable())
                .authorizeHttpRequests(requests -> requests.anyRequest().access((authentication, context) -> {
                    String supplied = context.getRequest().getHeader("X-Monitoring-Service-Key");
                    boolean allowed = "GET".equals(context.getRequest().getMethod()) && !key.isBlank() && supplied != null
                            && MessageDigest.isEqual(key.getBytes(StandardCharsets.UTF_8), supplied.getBytes(StandardCharsets.UTF_8));
                    return new org.springframework.security.authorization.AuthorizationDecision(allowed);
                }))
                .exceptionHandling(errors -> errors.authenticationEntryPoint((request, response, cause) -> response.setStatus(401))
                        .accessDeniedHandler((request, response, cause) -> response.setStatus(401)))
                .sessionManagement(session -> session.sessionCreationPolicy(org.springframework.security.config.http.SessionCreationPolicy.STATELESS))
                .build();
    }
}
