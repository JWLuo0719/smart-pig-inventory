package com.smartfarm.inventory.assistant;

import java.util.HashMap;
import java.util.Map;
import org.springframework.stereotype.Component;

/** Process-local admission bounds. Never logs or exports identity keys. */
@Component
public class AgentRequestLimiter {
    private final Map<String, Window> windows = new HashMap<>();
    private int active;
    public synchronized Lease acquire(String identity) {
        long now = System.nanoTime();
        windows.entrySet().removeIf(entry -> !entry.getValue().active && now - entry.getValue().started > 120_000_000_000L);
        Window window = windows.get(identity);
        if (window == null || (!window.active && now - window.started >= 60_000_000_000L)) {
            if (window == null && windows.size() >= 1024) throw new LimitException();
            window = new Window(now); windows.put(identity, window);
        }
        if (active >= 4 || window.active || window.count >= 12) throw new LimitException();
        window.active = true; window.count++; active++;
        return new Lease(window);
    }
    private static class Window {
        final long started; int count; boolean active;
        Window(long started) { this.started = started; }
    }
    public final class Lease implements AutoCloseable {
        private final Window window; private boolean closed;
        private Lease(Window window) { this.window = window; }
        @Override public void close() {
            synchronized (AgentRequestLimiter.this) {
                if (!closed) { closed = true; window.active = false; active--; }
            }
        }
    }
    public static class LimitException extends RuntimeException {}
}
