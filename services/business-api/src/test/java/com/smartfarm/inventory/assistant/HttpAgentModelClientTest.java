package com.smartfarm.inventory.assistant;

import static org.assertj.core.api.Assertions.*;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.sun.net.httpserver.HttpServer;
import java.net.InetSocketAddress;
import java.time.Duration;
import java.util.concurrent.atomic.AtomicReference;
import org.junit.jupiter.api.*;

class HttpAgentModelClientTest {
    private final ObjectMapper mapper = new ObjectMapper();
    private HttpServer server;
    @AfterEach void stop() { if (server != null) server.stop(0); }
    private String serve(int status, byte[] body, AtomicReference<String> request) throws Exception {
        server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        server.createContext("/chat/completions", exchange -> {
            request.set(new String(exchange.getRequestBody().readAllBytes(), java.nio.charset.StandardCharsets.UTF_8));
            exchange.sendResponseHeaders(status, body.length); exchange.getResponseBody().write(body); exchange.close();
        }); server.start(); return "http://127.0.0.1:" + server.getAddress().getPort() + "/chat/completions";
    }
    @Test void sendsRealHttpFunctionProtocolWithoutSdkAndReadsAssistantMessage() throws Exception {
        var sent = new AtomicReference<String>();
        String endpoint = serve(200, "{\"choices\":[{\"message\":{\"role\":\"assistant\",\"content\":\"fixture\"}}]}".getBytes(), sent);
        var client = new HttpAgentModelClient(mapper, true, true, endpoint, "synthetic-server-key", "fixture-model");
        var reply = client.complete(mapper.createArrayNode(), AgentToolDefinitions.definitions(mapper), Duration.ofSeconds(3));
        assertThat(reply.path("content").asText()).isEqualTo("fixture");
        assertThat(mapper.readTree(sent.get()).path("tools").size()).isEqualTo(3);
        assertThat(sent.get()).doesNotContain("synthetic-server-key");
    }
    @Test void nonSuccessAndOversizeBodiesAreSanitized() throws Exception {
        String endpoint = serve(429, "private upstream detail".getBytes(), new AtomicReference<>());
        var client = new HttpAgentModelClient(mapper, true, true, endpoint, "synthetic", "fixture");
        assertThatThrownBy(() -> client.complete(mapper.createArrayNode(), mapper.createArrayNode(), Duration.ofSeconds(2)))
                .isInstanceOf(AgentModelClient.ModelUnavailableException.class).hasMessage(null);
    }
    @Test void responseSizeIsBounded() throws Exception {
        String endpoint = serve(200, new byte[100000], new AtomicReference<>());
        var client = new HttpAgentModelClient(mapper, true, true, endpoint, "synthetic", "fixture");
        assertThatThrownBy(() -> client.complete(mapper.createArrayNode(), mapper.createArrayNode(), Duration.ofSeconds(3)))
                .isInstanceOf(AgentModelClient.ModelUnavailableException.class);
    }
    @Test void refusesInsecureRemoteCredentialUrlsAndAccidentalEgressEnablement() {
        for (String endpoint : java.util.List.of("http://remote.example/chat/completions", "https://user:secret@host/path", "https://host/path?api_key=secret", "file:///secret", "http:///secret")) {
            assertThatThrownBy(() -> new HttpAgentModelClient(mapper, false, false, endpoint, "", ""))
                    .isInstanceOf(IllegalArgumentException.class).hasMessageNotContaining("secret");
        }
        assertThatThrownBy(() -> new HttpAgentModelClient(mapper, true, false, "https://host/chat/completions", "key", "fixture"))
                .isInstanceOf(IllegalArgumentException.class);
    }
    @Test void slowBodyIsCancelledWithinTheWholeRequestDeadline() throws Exception {
        server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        server.createContext("/chat/completions", exchange -> {
            exchange.sendResponseHeaders(200, 100);
            try { Thread.sleep(1000); } catch (InterruptedException ignored) { Thread.currentThread().interrupt(); }
            exchange.close();
        }); server.start();
        var client = new HttpAgentModelClient(mapper, true, true, "http://127.0.0.1:" + server.getAddress().getPort() + "/chat/completions", "key", "fixture");
        long start = System.nanoTime();
        assertThatThrownBy(() -> client.complete(mapper.createArrayNode(), mapper.createArrayNode(), Duration.ofMillis(150)))
                .isInstanceOf(AgentModelClient.ModelUnavailableException.class);
        assertThat(Duration.ofNanos(System.nanoTime() - start)).isLessThan(Duration.ofMillis(900));
    }
}
