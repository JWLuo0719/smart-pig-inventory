package com.smartfarm.inventory.system;

import com.smartfarm.inventory.common.ApiEnvelope;
import com.smartfarm.inventory.common.CorrelationIdFilter;
import jakarta.servlet.http.HttpServletRequest;
import java.util.List;
import java.util.Map;
import java.util.LinkedHashMap;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1/system")
public class SystemController {
    private final InferenceCapabilities inference;

    public SystemController(InferenceCapabilities inference) {
        this.inference = inference;
    }

    @GetMapping("/capabilities")
    ApiEnvelope<Map<String, Object>> capabilities(HttpServletRequest request) {
        String correlationId = (String) request.getAttribute(CorrelationIdFilter.ATTRIBUTE);
        Map<String, Object> capabilities = new LinkedHashMap<>(Map.of(
                "product", "smart-pig-inventory",
                "api_version", "v1",
                "capture_kinds", List.of("single", "left_center_right", "video"),
                "video_counting", false,
                "on_device_counting", false,
                "fake_realtime_results", false));
        capabilities.putAll(inference.snapshot());
        return ApiEnvelope.ok(capabilities, correlationId);
    }
}
