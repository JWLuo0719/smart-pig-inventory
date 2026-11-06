package com.smartfarm.inventory.assistant;

import static org.assertj.core.api.Assertions.*;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.*;

class AssistantBodyLimitFilterTest {
    @Test void contentLengthLimitRejectsBeforeController() throws Exception {
        var request = new MockHttpServletRequest("POST", "/api/v1/assistant/chat"); request.setContent(new byte[65537]);
        var response = new MockHttpServletResponse(); var chain = new MockFilterChain();
        new AssistantBodyLimitFilter().doFilter(request, response, chain);
        assertThat(response.getStatus()).isEqualTo(413); assertThat(chain.getRequest()).isNull();
    }
    @Test void boundedBodyCanBeReadWithoutChangingIt() throws Exception {
        var request = new MockHttpServletRequest("POST", "/api/v1/assistant/chat"); request.setContent("{}".getBytes());
        var response = new MockHttpServletResponse();
        new AssistantBodyLimitFilter().doFilter(request, response, (wrapped, reply) -> {
            assertThat(wrapped.getInputStream().readAllBytes()).isEqualTo("{}".getBytes());
        });
    }
    @Test void validLongChineseContextFitsTheByteBudget() throws Exception {
        byte[] body = ("盘点".repeat(1000).repeat(7)).getBytes(java.nio.charset.StandardCharsets.UTF_8);
        var request = new MockHttpServletRequest("POST", "/api/v1/assistant/chat"); request.setContent(body);
        var response = new MockHttpServletResponse();
        new AssistantBodyLimitFilter().doFilter(request, response, (wrapped, reply) -> {
            assertThat(wrapped.getInputStream().readAllBytes()).isEqualTo(body);
        });
    }
}
