package com.smartfarm.inventory.inference;

import java.time.Duration;
import java.time.Instant;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

/**
 * 滞留任务回收器:回调 4xx 后 inference_job 会永远停在 submitted/processing,
 * 失败列表只查 status=failed,管理端既看不到也无法重试。这里把超时且无回调回执的任务
 * 置为 failed(INFERENCE_TIMEOUT)并写 audit_event,使其进入既有失败列表与重试通道。
 * app.inference.stale-job-timeout 设为 0(或 PT0S)可禁用回收。
 */
@Component
public class InferenceStaleJobReaper {
    private final JdbcInferenceRepository repository;
    private final Duration staleJobTimeout;

    public InferenceStaleJobReaper(
            JdbcInferenceRepository repository,
            @Value("${app.inference.stale-job-timeout:PT24H}") Duration staleJobTimeout) {
        this.repository = repository;
        this.staleJobTimeout = staleJobTimeout;
    }

    @Scheduled(fixedDelayString = "${app.inference.stale-job-reaper.fixed-delay:300000}")
    public void reapStaleJobs() {
        if (staleJobTimeout.isZero() || staleJobTimeout.isNegative()) {
            return;
        }
        for (JdbcInferenceRepository.StaleJob job : repository.findStaleJobs(Instant.now().minus(staleJobTimeout))) {
            repository.markTimedOut(job);
        }
    }
}
