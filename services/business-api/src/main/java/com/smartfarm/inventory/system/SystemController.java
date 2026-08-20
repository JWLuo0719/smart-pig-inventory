package com.smartfarm.inventory.system;

import com.smartfarm.inventory.common.ApiEnvelope;
import com.smartfarm.inventory.common.CorrelationIdFilter;
import com.smartfarm.inventory.inference.CountingProvider;
import jakarta.servlet.http.HttpServletRequest;
import java.util.List;
import java.util.Map;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1/system")
public class SystemController {
    private final CountingProvider countingProvider;

    public SystemController(CountingProvider countingProvider) {
        this.countingProvider = countingProvider;
    }

    @GetMapping("/capabilities")
    ApiEnvelope<Map<String, Object>> capabilities(HttpServletRequest request) {
        String correlationId = (String) request.getAttribute(CorrelationIdFilter.ATTRIBUTE);
        Map<String, Object> capabilities = Map.of(
                "product", "smart-pig-inventory",
                "api_version", "v1",
                "capture_kinds", List.of("single", "left_center_right"),
                "counting_provider", countingProvider.key(),
                "counting_available", !"unavailable".equals(countingProvider.key()),
                "video_counting", false,
                "on_device_counting", false,
                "fake_realtime_results", false);
        return ApiEnvelope.ok(capabilities, correlationId);
    }
}
