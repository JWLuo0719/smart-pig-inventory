package com.smartfarm.inventory.capture.ui;

import com.smartfarm.inventory.capture.application.UploadException;
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
import org.springframework.web.method.annotation.MethodArgumentTypeMismatchException;

@RestControllerAdvice
public class UploadProblemHandler {
    @ExceptionHandler(UploadException.class)
    ResponseEntity<Map<String, Object>> uploadException(UploadException exception, HttpServletRequest request) {
        return problem(exception.status(), exception.code(), exception.getMessage(), request);
    }

    @ExceptionHandler({IllegalArgumentException.class, MethodArgumentNotValidException.class, MethodArgumentTypeMismatchException.class})
    ResponseEntity<Map<String, Object>> validationException(Exception exception, HttpServletRequest request) {
        return problem(422, "UPLOAD_VALIDATION_FAILED", "The upload request does not meet the contract", request);
    }

    private ResponseEntity<Map<String, Object>> problem(int status, String code, String detail, HttpServletRequest request) {
        String correlationId = (String) request.getAttribute(CorrelationIdFilter.ATTRIBUTE);
        Map<String, Object> body = Map.of(
                "type", URI.create("https://smart-farm.invalid/problems/" + code.toLowerCase()),
                "title", HttpStatus.valueOf(status).getReasonPhrase(),
                "status", status,
                "detail", detail,
                "code", code,
                "correlationId", correlationId == null ? "unknown" : correlationId);
        return ResponseEntity.status(status).contentType(MediaType.valueOf("application/problem+json")).body(body);
    }
}
