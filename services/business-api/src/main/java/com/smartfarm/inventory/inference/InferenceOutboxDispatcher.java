package com.smartfarm.inventory.inference;

import jakarta.annotation.PostConstruct;
import jakarta.annotation.PreDestroy;
import java.time.Duration;
import java.time.Instant;
import java.util.Optional;
import java.util.concurrent.ScheduledFuture;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.http.client.ClientHttpRequestFactory;
import org.springframework.scheduling.concurrent.ThreadPoolTaskScheduler;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;

/**
 * Polls the transactional outbox. Delivery is at-least-once; the job and callback are idempotent.
 * 派发循环跑在独立 inference-dispatch 线程池上,HTTP 调用带超时:单次挂起既不能堵死共享调度线程,也不会永久占死派发线程。
 */
@Component
@ConditionalOnProperty(name = "app.inference.dispatcher.enabled", havingValue = "true")
public class InferenceOutboxDispatcher {
    private final JdbcInferenceRepository repository;
    private final RestClient inferenceClient;
    private final ThreadPoolTaskScheduler dispatchScheduler;
    private final Duration fixedDelay;
    private ScheduledFuture<?> dispatchLoop;

    public InferenceOutboxDispatcher(
            JdbcInferenceRepository repository,
            @Value("${app.inference.base-url}") String baseUrl,
            ClientHttpRequestFactory inferenceRequestFactory,
            @Qualifier("inferenceDispatchScheduler") ThreadPoolTaskScheduler dispatchScheduler,
            @Value("${app.inference.dispatcher.fixed-delay:2000}") long fixedDelayMillis) {
        this.repository = repository;
        this.inferenceClient = RestClient.builder().baseUrl(baseUrl).requestFactory(inferenceRequestFactory).build();
        this.dispatchScheduler = dispatchScheduler;
        this.fixedDelay = Duration.ofMillis(fixedDelayMillis);
    }

    @PostConstruct
    void startDispatchLoop() {
        // 不用 @Scheduled:共享 taskScheduler 只有一个线程,派发必须隔离在独立线程池上。
        dispatchLoop = dispatchScheduler.scheduleWithFixedDelay(this::dispatchSafely, Instant.now(), fixedDelay);
    }

    @PreDestroy
    void stopDispatchLoop() {
        if (dispatchLoop != null) {
            dispatchLoop.cancel(false);
        }
    }

    void dispatchSafely() {
        try {
            dispatchAvailable();
        } catch (RuntimeException ignored) {
            // 派发循环不能因一次数据库抖动而永久停止;下一轮延迟后继续。
        }
    }

    public void dispatchAvailable() {
        Optional<JdbcInferenceRepository.DispatchableJob> claimed = repository.claimNext(Duration.ofMinutes(5));
        if (claimed.isEmpty()) {
            return;
        }
        JdbcInferenceRepository.DispatchableJob job = claimed.get();
        try {
            inferenceClient.post().uri("/v1/jobs").body(job.request()).retrieve().toBodilessEntity();
            repository.markPublished(job.eventId(), job.attempt(), job.jobId());
        } catch (RuntimeException exception) {
            repository.markRetry(job.eventId(), job.attempt(), 5,
                    exception.getClass().getSimpleName() + ": " + exception.getMessage());
        }
    }
}
