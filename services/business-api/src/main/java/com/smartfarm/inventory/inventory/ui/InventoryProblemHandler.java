package com.smartfarm.inventory.inventory.ui;

import com.smartfarm.inventory.common.CorrelationIdFilter;
import com.smartfarm.inventory.inventory.application.InventoryException;
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

@RestControllerAdvice(basePackageClasses = InventoryReviewController.class)
public class InventoryProblemHandler {
    @ExceptionHandler(InventoryException.class)
    ResponseEntity<Map<String, Object>> inventoryException(InventoryException exception, HttpServletRequest request) {
        return problem(exception.status(), exception.code(), exception.getMessage(), request);
    }

    @ExceptionHandler({IllegalArgumentException.class, MethodArgumentNotValidException.class, MethodArgumentTypeMismatchException.class})
    ResponseEntity<Map<String, Object>> validationException(Exception exception, HttpServletRequest request) {
        return problem(422, "INVENTORY_VALIDATION_FAILED", "The inventory review request does not meet the contract", request);
    }

    private ResponseEntity<Map<String, Object>> problem(int status, String code, String detail, HttpServletRequest request) {
        Object correlation = request.getAttribute(CorrelationIdFilter.ATTRIBUTE);
        Map<String, Object> body = Map.of(
                "type", URI.create("https://smart-farm.invalid/problems/" + code.toLowerCase()),
                "title", HttpStatus.valueOf(status).getReasonPhrase(), "status", status, "detail", detail,
                "code", code, "correlationId", correlation == null ? "unknown" : correlation.toString());
        return ResponseEntity.status(status).contentType(MediaType.valueOf("application/problem+json")).body(body);
    }
}
