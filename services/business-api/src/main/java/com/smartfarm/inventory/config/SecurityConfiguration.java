package com.smartfarm.inventory.config;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.security.config.Customizer;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.web.SecurityFilterChain;

@Configuration
public class SecurityConfiguration {
    @Bean
    SecurityFilterChain securityFilterChain(
            HttpSecurity http,
            @Value("${app.security.enabled:true}") boolean securityEnabled) throws Exception {
        http.csrf(csrf -> csrf.disable());
        if (securityEnabled) {
            http.authorizeHttpRequests(authorize -> authorize
                            .requestMatchers("/actuator/health/**", "/api/v1/system/capabilities").permitAll()
                            .anyRequest().authenticated())
                    .oauth2ResourceServer(resourceServer -> resourceServer.jwt(Customizer.withDefaults()));
        } else {
            http.authorizeHttpRequests(authorize -> authorize.anyRequest().permitAll());
        }
        return http.build();
    }
}

