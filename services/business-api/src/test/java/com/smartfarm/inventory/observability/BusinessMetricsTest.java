package com.smartfarm.inventory.observability;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.*;
import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import java.util.Map;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.web.servlet.HandlerMapping;

class BusinessMetricsTest {
    @Test void snapshotIsUnknownBeforeSuccessAndAfterFailureAndCanRecover() {
        var repository = mock(BusinessMetricsSnapshotRepository.class);
        var meters = new SimpleMeterRegistry();
        var metrics = new BusinessMetrics(repository, meters);
        assertThat(meters.get("pig.inventory.review.pending").gauge().value()).isNaN();
        when(repository.read()).thenReturn(Map.of("pig.inventory.review.pending", 3.0))
                .thenThrow(new IllegalStateException("secret SQL"))
                .thenReturn(Map.of("pig.inventory.review.pending", 0.0));
        metrics.refresh();
        assertThat(meters.get("pig.inventory.review.pending").gauge().value()).isEqualTo(3);
        assertThat(meters.get("pig.metrics.snapshot.available").gauge().value()).isEqualTo(1);
        metrics.refresh();
        assertThat(meters.get("pig.inventory.review.pending").gauge().value()).isNaN();
        assertThat(meters.get("pig.metrics.snapshot.available").gauge().value()).isZero();
        metrics.refresh();
        assertThat(meters.get("pig.inventory.review.pending").gauge().value()).isZero();
        assertThat(meters.get("pig.metrics.snapshot.last.success.timestamp.seconds").gauge().value()).isPositive();
        assertThat(meters.getMeters()).allSatisfy(meter -> assertThat(meter.getId().getTags()).isEmpty());
    }

    @Test void uploadAttemptsDistinguishNewReplayRejectionAndFailureWithBoundedLabels() {
        var meters = new SimpleMeterRegistry();
        var metrics = new UploadMetricsConfiguration(meters);
        for (int status : new int[] {201, 200, 409, 500}) {
            var request = new MockHttpServletRequest("POST", "/api/v1/upload-packages/private-id/commit");
            request.setAttribute(HandlerMapping.BEST_MATCHING_PATTERN_ATTRIBUTE, "/api/v1/upload-packages/{packageId}/commit");
            if (status == 409) request.setAttribute(UploadMetricsConfiguration.ERROR_CODE, "EXACT_DUPLICATE_IMAGE");
            var response = new MockHttpServletResponse(); response.setStatus(status);
            metrics.afterCompletion(request, response, new Object(), null);
        }
        for (String outcome : new String[] {"created", "replayed", "rejected", "failed"}) {
            assertThat(meters.get("pig.upload.requests").tags("step", "commit", "outcome", outcome).counter().count()).isEqualTo(1);
        }
        assertThat(meters.get("pig.upload.duplicate.rejections").counter().count()).isEqualTo(1);
        metrics.afterCompletion(new MockHttpServletRequest("GET", "/private/unmatched"), new MockHttpServletResponse(), new Object(), null);
        assertThat(meters.getMeters()).hasSize(17).allSatisfy(meter -> assertThat(meter.getId().toString()).doesNotContain("private"));
    }
}
