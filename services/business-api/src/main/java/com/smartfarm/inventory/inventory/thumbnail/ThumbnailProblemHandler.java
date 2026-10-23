package com.smartfarm.inventory.inventory.thumbnail;

import com.smartfarm.inventory.common.CorrelationIdFilter;
import com.smartfarm.inventory.inventory.application.InventoryException;
import jakarta.servlet.http.HttpServletRequest;
import java.util.Map;
import org.springframework.http.CacheControl;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

@RestControllerAdvice(assignableTypes = ThumbnailController.class)
public class ThumbnailProblemHandler {
    @ExceptionHandler(ThumbnailException.class)
    ResponseEntity<Map<String, Object>> thumbnail(ThumbnailException exception, HttpServletRequest request) {
        return problem(exception.status(), exception.code(), exception.getMessage(), request);
    }

    @ExceptionHandler(InventoryException.class)
    ResponseEntity<Map<String, Object>> inventory(InventoryException exception, HttpServletRequest request) {
        return problem(exception.status(), exception.code(), exception.getMessage(), request);
    }

    private ResponseEntity<Map<String, Object>> problem(int status, String code, String detail, HttpServletRequest request) {
        Object correlation = request.getAttribute(CorrelationIdFilter.ATTRIBUTE);
        return ResponseEntity.status(status).cacheControl(CacheControl.noStore()).contentType(MediaType.APPLICATION_PROBLEM_JSON)
                .body(Map.of("type", "https://smart-farm.invalid/problems/" + code.toLowerCase(java.util.Locale.ROOT),
                        "title", HttpStatus.valueOf(status).getReasonPhrase(), "status", status, "detail", detail,
                        "code", code, "correlationId", correlation == null ? "unknown" : correlation.toString()));
    }
}
