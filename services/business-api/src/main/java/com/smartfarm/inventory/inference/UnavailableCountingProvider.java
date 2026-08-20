package com.smartfarm.inventory.inference;

import java.util.List;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Component;

@Component
@ConditionalOnProperty(name = "app.inference.provider", havingValue = "unavailable", matchIfMissing = true)
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
