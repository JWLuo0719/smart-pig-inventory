package com.smartfarm.inventory.assistant;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

@Component
public class HttpAgentModelClient implements AgentModelClient {
    private final ObjectMapper mapper;
    private final boolean enabled;
    private final URI endpoint;
    private final String apiKey;
    private final String model;
    private final HttpClient http = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(5))
            .followRedirects(HttpClient.Redirect.NEVER).build();

    public HttpAgentModelClient(ObjectMapper mapper,
            @Value("${app.assistant.enabled:false}") boolean enabled,
            @Value("${app.assistant.data-egress-approved:false}") boolean egressApproved,
            @Value("${app.assistant.endpoint:}") String endpoint,
            @Value("${app.assistant.api-key:}") String apiKey,
            @Value("${app.assistant.model:}") String model) {
        this.mapper = mapper; this.enabled = enabled && egressApproved;
        this.apiKey = apiKey; this.model = model;
        this.endpoint = endpoint.isBlank() ? null : validatedEndpoint(endpoint);
        if (enabled && (!egressApproved || this.endpoint == null || apiKey.isBlank() || model.isBlank())) {
            throw new IllegalArgumentException("Enabled assistant requires approved egress, endpoint, model and server credential");
        }
    }

    static URI validatedEndpoint(String value) {
        try {
            URI uri = URI.create(value);
            boolean loopback = "http".equals(uri.getScheme()) && uri.getHost() != null
                    && java.util.Set.of("localhost", "127.0.0.1", "[::1]").contains(uri.getHost());
            if (!("https".equals(uri.getScheme()) || loopback) || uri.getHost() == null
                    || uri.getRawUserInfo() != null || uri.getRawQuery() != null || uri.getRawFragment() != null) {
                throw new IllegalArgumentException();
            }
            return uri;
        } catch (IllegalArgumentException exception) { throw new IllegalArgumentException("Invalid assistant endpoint configuration"); }
    }

    @Override public boolean available() { return enabled && endpoint != null && !apiKey.isBlank() && !model.isBlank(); }
    @Override public String model() { return available() ? model : "unconfigured"; }

    @Override public JsonNode complete(JsonNode messages, JsonNode tools, Duration timeout) {
        if (!available() || timeout.isNegative() || timeout.isZero()) throw new ModelUnavailableException();
        var payload = mapper.createObjectNode().put("model", model).put("stream", false).put("max_tokens", 1000);
        payload.set("messages", messages); payload.set("tools", tools); payload.put("tool_choice", "auto");
        try {
            byte[] body = mapper.writeValueAsBytes(payload);
            if (body.length > 131072) throw new ModelUnavailableException();
            var request = HttpRequest.newBuilder(endpoint).timeout(timeout.compareTo(Duration.ofSeconds(25)) > 0 ? Duration.ofSeconds(25) : timeout)
                    .header("Content-Type", "application/json").header("Authorization", "Bearer " + apiKey)
                    .POST(HttpRequest.BodyPublishers.ofByteArray(body)).build();
            // Byte-array subscriber is bounded and cancellation also covers a slow/dripping body.
            var pending = http.sendAsync(request, info -> new LimitedBodySubscriber(98304));
            HttpResponse<byte[]> response;
            try { response = pending.get(Math.min(timeout.toMillis(), 25000), java.util.concurrent.TimeUnit.MILLISECONDS); }
            catch (java.util.concurrent.TimeoutException | java.util.concurrent.ExecutionException exception) {
                pending.cancel(true); throw new ModelUnavailableException();
            } catch (InterruptedException exception) { pending.cancel(true); throw exception; }
            if (response.statusCode() != 200) throw new ModelUnavailableException();
            JsonNode result = mapper.readTree(response.body());
            JsonNode message = result.path("choices").path(0).path("message");
            if (!message.isObject() || !"assistant".equals(message.path("role").asText())) throw new ModelUnavailableException();
            var safeMessage = ((com.fasterxml.jackson.databind.node.ObjectNode) message).deepCopy();
            var usage = safeMessage.putObject("_usage");
            for (String key : java.util.List.of("prompt_tokens", "completion_tokens", "total_tokens")) {
                JsonNode count = result.path("usage").path(key);
                if (count.isIntegralNumber() && count.canConvertToLong() && count.longValue() >= 0) usage.put(key, count.longValue());
            }
            return safeMessage;
        } catch (InterruptedException exception) {
            Thread.currentThread().interrupt(); throw new ModelUnavailableException();
        } catch (IOException | IllegalArgumentException exception) { throw new ModelUnavailableException(); }
    }

    /** Retains at most limit bytes; the HttpRequest deadline applies until completion. */
    static final class LimitedBodySubscriber implements HttpResponse.BodySubscriber<byte[]> {
        private final int limit;
        private final java.io.ByteArrayOutputStream bytes = new java.io.ByteArrayOutputStream();
        private final java.util.concurrent.CompletableFuture<byte[]> result = new java.util.concurrent.CompletableFuture<>();
        private java.util.concurrent.Flow.Subscription subscription;
        LimitedBodySubscriber(int limit) { this.limit = limit; }
        @Override public java.util.concurrent.CompletionStage<byte[]> getBody() { return result; }
        @Override public void onSubscribe(java.util.concurrent.Flow.Subscription value) { subscription = value; value.request(1); }
        @Override public void onNext(java.util.List<java.nio.ByteBuffer> buffers) {
            for (var buffer : buffers) {
                if (buffer.remaining() > limit - bytes.size()) { subscription.cancel(); result.completeExceptionally(new IOException("Model response limit")); return; }
                byte[] chunk = new byte[buffer.remaining()]; buffer.get(chunk); bytes.writeBytes(chunk);
            }
            subscription.request(1);
        }
        @Override public void onError(Throwable error) { result.completeExceptionally(error); }
        @Override public void onComplete() { result.complete(bytes.toByteArray()); }
    }
}
