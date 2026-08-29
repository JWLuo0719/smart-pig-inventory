package com.smartfarm.inventory.inference;

import java.time.Duration;
import java.util.Optional;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;

/** Polls the transactional outbox. Delivery is at-least-once; the job and callback are idempotent. */
@Component
@ConditionalOnProperty(name = "app.inference.dispatcher.enabled", havingValue = "true")
public class InferenceOutboxDispatcher {
    private final JdbcInferenceRepository repository;
    private final RestClient inferenceClient;

    public InferenceOutboxDispatcher(
            JdbcInferenceRepository repository,
            @Value("${app.inference.base-url}") String baseUrl) {
        this.repository = repository;
        this.inferenceClient = RestClient.builder().baseUrl(baseUrl).build();
    }

    @Scheduled(fixedDelayString = "${app.inference.dispatcher.fixed-delay:2000}")
    public void dispatchAvailable() {
        Optional<JdbcInferenceRepository.DispatchableJob> claimed = repository.claimNext(Duration.ofMinutes(5));
        if (claimed.isEmpty()) {
            return;
        }
        JdbcInferenceRepository.DispatchableJob job = claimed.get();
        try {
            inferenceClient.post().uri("/v1/jobs").body(job.request()).retrieve().toBodilessEntity();
            repository.markPublished(job.eventId(), job.jobId());
        } catch (RuntimeException exception) {
            repository.markRetry(job.eventId(), 5, exception.getClass().getSimpleName() + ": " + exception.getMessage());
        }
    }
}
