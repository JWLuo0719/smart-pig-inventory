package com.smartfarm.inventory.inference;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.client.ClientHttpRequestFactory;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.scheduling.concurrent.ThreadPoolTaskScheduler;

/** 推理派发独占调度池与带超时的 HTTP 工厂:单次挂起既不能堵死共享调度线程,也不能永久占死派发线程。 */
@Configuration
public class InferenceDispatchSchedulingConfiguration {
    @Bean
    public ThreadPoolTaskScheduler inferenceDispatchScheduler() {
        var scheduler = new ThreadPoolTaskScheduler();
        scheduler.setPoolSize(2);
        scheduler.setThreadNamePrefix("inference-dispatch-");
        scheduler.setDaemon(true);
        scheduler.setWaitForTasksToCompleteOnShutdown(false);
        scheduler.setRemoveOnCancelPolicy(true);
        return scheduler;
    }

    /** 派发 HTTP 调用必须带超时(connect 5s / read 60s),否则一次挂起就把派发线程永久占死。 */
    @Bean
    public ClientHttpRequestFactory inferenceRequestFactory() {
        SimpleClientHttpRequestFactory factory = new SimpleClientHttpRequestFactory();
        factory.setConnectTimeout(5_000);
        factory.setReadTimeout(60_000);
        return factory;
    }
}
