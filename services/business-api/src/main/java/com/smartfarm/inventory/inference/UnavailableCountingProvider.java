package com.smartfarm.inventory.inference;

import java.util.List;
import org.springframework.context.annotation.Primary;
import org.springframework.stereotype.Component;

/**
 * 兜底计数 Provider:未配置/未知 COUNTING_PROVIDER 时一律走人工复核,不产生自动数量。
 * 无条件注册并标 @Primary——Java 侧目前无其它实现,属性值为 research-http-yolo 等
 * 推理侧取值时同样需要该兜底(原先按属性值匹配会启动失败)。将来若增加真实 Provider,
 * 由新实现替换 @Primary 或注入点加 @Qualifier,本类降级为纯兜底。
 */
@Primary
@Component
public class UnavailableCountingProvider implements CountingProvider {
    @Override
    public String key() {
        return "unavailable";
    }

    @Override
    public CountingResult count(CountingRequest request) {
        CountingRequest.ModelIdentity model = request.requestedModel();
        return new CountingResult(
                CountingResult.Status.REVIEW_REQUIRED,
                null,
                List.of(),
                List.of("No validated counting provider is configured"),
                model.modelKey(),
                model.version(),
                model.checksum(),
                model.adapterVersion(),
                key(),
                0);
    }
}
