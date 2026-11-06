package com.smartfarm.inventory.assistant;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;

public final class AgentToolDefinitions {
    private AgentToolDefinitions() {}
    public static JsonNode definitions(ObjectMapper mapper) {
        try {
            return mapper.readTree("""
                    [
                      {"type":"function","function":{"name":"inspect_session","description":"读取受权会话的候选、确认和问题分类；不执行确认或更正。","parameters":{"type":"object","additionalProperties":false,"properties":{"sessionId":{"type":"string","format":"uuid"}},"required":["sessionId"]}}},
                      {"type":"function","function":{"name":"get_day_overview","description":"读取指定业务日启用栏舍覆盖、确认汇总和有限待办行；hasMore表示行截断。","parameters":{"type":"object","additionalProperties":false,"properties":{"businessDate":{"type":"string","format":"date"},"limit":{"type":"integer","minimum":1,"maximum":50,"default":20}},"required":["businessDate"]}}},
                      {"type":"function","function":{"name":"get_pen_history","description":"读取启用栏舍连续日期的确认历史；缺失为null。只提供最多50条引用，不能推断疾病或转出原因。","parameters":{"type":"object","additionalProperties":false,"properties":{"penId":{"type":"string","format":"uuid"},"to":{"type":"string","format":"date"},"days":{"type":"integer","minimum":1,"maximum":90,"default":7}},"required":["penId","to"]}}}
                    ]
                    """);
        } catch (java.io.IOException exception) { throw new IllegalStateException("Invalid packaged tool definitions", exception); }
    }
}
