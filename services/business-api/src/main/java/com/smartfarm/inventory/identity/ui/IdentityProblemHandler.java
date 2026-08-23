package com.smartfarm.inventory.identity.ui;

import com.smartfarm.inventory.common.CorrelationIdFilter;
import com.smartfarm.inventory.identity.application.IdentityException;
import jakarta.servlet.http.HttpServletRequest;
import java.net.URI;
import java.util.Map;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

@RestControllerAdvice
public class IdentityProblemHandler {
    @ExceptionHandler(IdentityException.class)
    ResponseEntity<Map<String, Object>> identityException(IdentityException exception, HttpServletRequest request) {
        String correlationId = (String) request.getAttribute(CorrelationIdFilter.ATTRIBUTE);
        Map<String, Object> body = Map.of(
                "type", URI.create("https://smart-farm.invalid/problems/" + exception.code().toLowerCase()),
                "title", HttpStatus.valueOf(exception.status()).getReasonPhrase(),
                "status", exception.status(),
                "detail", exception.getMessage(),
                "code", exception.code(),
                "correlationId", correlationId == null ? "unknown" : correlationId);
        return ResponseEntity.status(exception.status())
                .contentType(MediaType.valueOf("application/problem+json"))
                .body(body);
    }
}
