package com.smartfarm.inventory.inference;

import com.smartfarm.inventory.common.CorrelationIdFilter;
import jakarta.servlet.http.HttpServletRequest;
import java.net.URI;
import java.util.Map;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

@RestControllerAdvice(basePackageClasses = InferenceResultController.class)
public class InferenceProblemHandler {
    @ExceptionHandler(InferenceException.class)
    ResponseEntity<Map<String, Object>> inferenceException(InferenceException exception, HttpServletRequest request) {
        return problem(exception.status(), exception.code(), exception.getMessage(), request);
    }

    @ExceptionHandler({IllegalArgumentException.class, MethodArgumentNotValidException.class})
    ResponseEntity<Map<String, Object>> validationException(Exception exception, HttpServletRequest request) {
        return problem(422, "INFERENCE_RESULT_INVALID", "The inference result does not meet the contract", request);
    }

    private ResponseEntity<Map<String, Object>> problem(int status, String code, String detail, HttpServletRequest request) {
        String correlationId = (String) request.getAttribute(CorrelationIdFilter.ATTRIBUTE);
        Map<String, Object> body = Map.of(
                "type", URI.create("https://smart-farm.invalid/problems/" + code.toLowerCase()),
                "title", HttpStatus.valueOf(status).getReasonPhrase(), "status", status, "detail", detail,
                "code", code, "correlationId", correlationId == null ? "unknown" : correlationId);
        return ResponseEntity.status(status).contentType(MediaType.valueOf("application/problem+json")).body(body);
    }
}
