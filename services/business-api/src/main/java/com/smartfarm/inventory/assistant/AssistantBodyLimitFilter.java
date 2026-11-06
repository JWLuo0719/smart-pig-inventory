package com.smartfarm.inventory.assistant;

import jakarta.servlet.*;
import jakarta.servlet.http.*;
import java.io.*;
import org.springframework.core.Ordered;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

@Component
@Order(Ordered.HIGHEST_PRECEDENCE + 20)
public class AssistantBodyLimitFilter extends OncePerRequestFilter {
    private static final int LIMIT = 65536;
    @Override protected boolean shouldNotFilter(HttpServletRequest request) {
        return !"POST".equals(request.getMethod()) || !request.getRequestURI().startsWith("/api/v1/assistant/");
    }
    @Override protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain)
            throws ServletException, IOException {
        if (request.getContentLengthLong() > LIMIT) {
            response.setStatus(413); response.setContentType("application/json");
            response.getWriter().write("{\"code\":\"ASSISTANT_REQUEST_TOO_LARGE\",\"message\":\"问题内容过长，请缩短后重试。\"}"); return;
        }
        chain.doFilter(new HttpServletRequestWrapper(request) {
            private ServletInputStream limited;
            @Override public ServletInputStream getInputStream() throws IOException {
                if (limited == null) {
                    ServletInputStream source = request.getInputStream();
                    limited = new ServletInputStream() {
                        private int size;
                        @Override public int read() throws IOException {
                            int value = source.read(); if (value >= 0 && ++size > LIMIT) throw new IOException("Assistant request limit"); return value;
                        }
                        @Override public int read(byte[] buffer, int offset, int length) throws IOException {
                            int count = source.read(buffer, offset, Math.min(length, LIMIT - size + 1));
                            if (count > 0 && (size += count) > LIMIT) throw new IOException("Assistant request limit"); return count;
                        }
                        @Override public boolean isFinished() { return source.isFinished(); }
                        @Override public boolean isReady() { return source.isReady(); }
                        @Override public void setReadListener(ReadListener listener) { source.setReadListener(listener); }
                    };
                }
                return limited;
            }
            @Override public BufferedReader getReader() throws IOException { return new BufferedReader(new InputStreamReader(getInputStream(), java.nio.charset.StandardCharsets.UTF_8)); }
        }, response);
    }
}
