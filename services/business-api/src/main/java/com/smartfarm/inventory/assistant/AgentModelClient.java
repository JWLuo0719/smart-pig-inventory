package com.smartfarm.inventory.assistant;

import com.fasterxml.jackson.databind.JsonNode;
import java.time.Duration;

/** Provider-neutral HTTP transport; never receives a business JWT. */
public interface AgentModelClient {
    boolean available();
    String model();
    JsonNode complete(JsonNode messages, JsonNode tools, Duration timeout);
    class ModelUnavailableException extends RuntimeException {}
}
