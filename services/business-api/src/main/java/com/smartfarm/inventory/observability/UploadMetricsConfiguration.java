package com.smartfarm.inventory.observability;

import io.micrometer.core.instrument.MeterRegistry;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.util.Map;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.servlet.HandlerInterceptor;
import org.springframework.web.servlet.HandlerMapping;
import org.springframework.web.servlet.config.annotation.InterceptorRegistry;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;

/** Counts completed MVC request attempts, not unique packages or uploaded images. */
@Configuration
public class UploadMetricsConfiguration implements WebMvcConfigurer, HandlerInterceptor {
    public static final String ERROR_CODE = "pig.upload.error.code";
    private static final Map<String, String> STEPS = Map.of(
            "POST /api/v1/upload-packages", "create",
            "PUT /api/v1/upload-packages/{packageId}/blobs/{assetId}", "blob",
            "PUT /api/v1/upload-packages/{packageId}/manifest", "manifest",
            "POST /api/v1/upload-packages/{packageId}/commit", "commit");
    private final MeterRegistry meters;

    public UploadMetricsConfiguration(MeterRegistry meters) {
        this.meters = meters;
        for (String step : STEPS.values()) for (String outcome : new String[] {"created", "replayed", "rejected", "failed"}) {
            meters.counter("pig.upload.requests", "step", step, "outcome", outcome);
        }
        meters.counter("pig.upload.duplicate.rejections");
    }

    @Override public void addInterceptors(InterceptorRegistry registry) { registry.addInterceptor(this); }

    @Override public void afterCompletion(HttpServletRequest request, HttpServletResponse response, Object handler, Exception error) {
        String step = STEPS.get(request.getMethod() + " " + request.getAttribute(HandlerMapping.BEST_MATCHING_PATTERN_ATTRIBUTE));
        if (step == null) return;
        int status = response.getStatus();
        String outcome = error != null || status >= 500 ? "failed" : status == 201 ? "created" : status >= 200 && status < 300 ? "replayed" : "rejected";
        meters.counter("pig.upload.requests", "step", step, "outcome", outcome).increment();
        if ("EXACT_DUPLICATE_IMAGE".equals(request.getAttribute(ERROR_CODE))) meters.counter("pig.upload.duplicate.rejections").increment();
    }
}
