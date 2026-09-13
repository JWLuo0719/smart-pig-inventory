package com.smartfarm.inventory.observability;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.scheduling.concurrent.ThreadPoolTaskScheduler;

/** A slow monitoring read must never occupy the inference dispatch scheduling thread. */
@Configuration
public class MetricsSchedulingConfiguration {
    @Bean public ThreadPoolTaskScheduler businessMetricsScheduler() { return scheduler("business-metrics-"); }
    @Bean public ThreadPoolTaskScheduler taskScheduler() { return scheduler("business-tasks-"); }

    private ThreadPoolTaskScheduler scheduler(String prefix) {
        var scheduler = new ThreadPoolTaskScheduler();
        scheduler.setPoolSize(1);
        scheduler.setThreadNamePrefix(prefix);
        scheduler.setDaemon(true);
        scheduler.setWaitForTasksToCompleteOnShutdown(false);
        scheduler.setRemoveOnCancelPolicy(true);
        return scheduler;
    }
}
