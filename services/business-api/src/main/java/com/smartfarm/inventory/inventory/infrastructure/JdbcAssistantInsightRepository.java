package com.smartfarm.inventory.inventory.infrastructure;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.time.LocalDate;
import java.util.List;
import java.util.UUID;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.stereotype.Repository;

/**
 * 智能体洞察的只读查询：一次取出组织在某业务日每个栏舍的会话状态、推理结果
 * 与最近一次历史确认，供 {@code AssistantInsightService} 生成带证据的研判。
 */
@Repository
public class JdbcAssistantInsightRepository {

    private final JdbcTemplate jdbc;
    private final ObjectMapper objectMapper;

    public JdbcAssistantInsightRepository(JdbcTemplate jdbc, ObjectMapper objectMapper) {
        this.jdbc = jdbc;
        this.objectMapper = objectMapper;
    }

    public List<AssistantRow> listOrganizationDay(UUID organizationId, LocalDate businessDate) {
        return jdbc.query("""
                SELECT p.id AS pen_id, b.code AS building_code, b.name AS building_name,
                       p.code AS pen_code, p.name AS pen_name,
                       s.id AS session_id, s.status, s.candidate_count, s.confirmed_count,
                       j.status AS inference_status, j.failure_code,
                       IFNULL(JSON_LENGTH(r.detections_json), 0) AS detection_count,
                       r.warnings_json,
                       last.business_date AS last_confirmed_date, last.confirmed_count AS last_confirmed_count
                FROM pen p
                JOIN building b ON b.id = p.building_id
                LEFT JOIN inventory_session s ON s.id = (
                    SELECT c.id FROM inventory_session c
                    WHERE c.pen_id = p.id AND c.business_date = ? AND c.status <> 'superseded'
                    ORDER BY (c.status = 'confirmed') DESC, c.updated_at DESC, c.created_at DESC, c.id DESC
                    LIMIT 1
                )
                LEFT JOIN inference_job j ON j.id = (
                    SELECT candidate.id FROM inference_job candidate
                    WHERE candidate.session_id = COALESCE(s.evidence_session_id, s.id)
                    ORDER BY candidate.retry_sequence DESC
                    LIMIT 1
                )
                LEFT JOIN count_result r ON r.inference_job_id = j.id
                LEFT JOIN inventory_session last ON last.id = (
                    SELECT c.id FROM inventory_session c
                    WHERE c.pen_id = p.id AND c.status = 'confirmed' AND c.business_date < ?
                    ORDER BY c.business_date DESC, c.confirmed_at DESC, c.id DESC
                    LIMIT 1
                )
                WHERE b.organization_id = ? AND b.enabled = TRUE AND p.enabled = TRUE
                ORDER BY b.code, p.code
                """, new AssistantRowMapper(), businessDate, businessDate, uuidToBytes(organizationId));
    }

    /**
     * 每栏最近一段确认历史（不含 businessDate 当天），用于基线偏离与
     * 采集断档等可解释规则；只取已确认会话，保持“机器提议、人签字”口径。
     */
    public List<PenHistoryRow> listConfirmedHistory(UUID organizationId, LocalDate beforeDate, int days) {
        return jdbc.query("""
                SELECT p.id AS pen_id, p.code AS pen_code, p.name AS pen_name,
                       b.code AS building_code, b.name AS building_name,
                       c.business_date, c.confirmed_count
                FROM inventory_session c
                JOIN pen p ON p.id = c.pen_id
                JOIN building b ON b.id = p.building_id
                WHERE b.organization_id = ? AND b.enabled = TRUE AND p.enabled = TRUE
                  AND c.status = 'confirmed'
                  AND c.business_date < ? AND c.business_date >= DATE_SUB(?, INTERVAL ? DAY)
                ORDER BY p.id, c.business_date
                """, (resultSet, rowNumber) -> new PenHistoryRow(
                readUuid(resultSet, "pen_id"), resultSet.getString("pen_code"), resultSet.getString("pen_name"),
                resultSet.getString("building_code"), resultSet.getString("building_name"),
                resultSet.getObject("business_date", LocalDate.class), resultSet.getInt("confirmed_count")),
                uuidToBytes(organizationId), beforeDate, beforeDate, days);
    }

    public record PenHistoryRow(UUID penId, String penCode, String penName, String buildingCode,
            String buildingName, LocalDate businessDate, int confirmedCount) {
    }

    private static UUID readUuid(ResultSet resultSet, String column) {
        try {
            return bytesToUuid(resultSet.getBytes(column));
        } catch (SQLException exception) {
            throw new IllegalStateException("Could not read uuid column " + column, exception);
        }
    }

    private static byte[] uuidToBytes(UUID value) {
        return java.nio.ByteBuffer.allocate(16)
                .putLong(value.getMostSignificantBits())
                .putLong(value.getLeastSignificantBits())
                .array();
    }

    private static UUID bytesToUuid(byte[] bytes) throws SQLException {
        if (bytes == null) {
            return null;
        }
        java.nio.ByteBuffer buffer = java.nio.ByteBuffer.wrap(bytes);
        return new UUID(buffer.getLong(), buffer.getLong());
    }

    private List<String> parseWarnings(String warningsJson) {
        if (warningsJson == null || warningsJson.isBlank()) {
            return List.of();
        }
        try {
            return objectMapper.readValue(warningsJson, new TypeReference<List<String>>() {});
        } catch (JsonProcessingException exception) {
            return List.of();
        }
    }

    /**
     * 每栏一行：今日会话与推理状态 + 最近一次历史确认（可能为空）。
     *
     * @param penId 栏舍 ID
     * @param buildingCode 栋舍编码
     * @param buildingName 栋舍名称
     * @param penCode 栏舍编码
     * @param penName 栏舍名称
     * @param sessionId 今日会话（未采集为 null）
     * @param status 会话状态（未采集为 null）
     * @param candidateCount 候选数量（研究通道可能为 null）
     * @param confirmedCount 已确认数量
     * @param inferenceStatus 最近一次推理任务状态
     * @param failureCode 推理失败码
     * @param detectionCount 检测框数量（候选为空时的替代口径）
     * @param warnings 推理警告
     * @param lastConfirmedDate 上次确认的业务日期
     * @param lastConfirmedCount 上次确认数量
     */
    public record AssistantRow(UUID penId, String buildingCode, String buildingName, String penCode,
                        String penName, UUID sessionId, String status, Integer candidateCount,
                        Integer confirmedCount, String inferenceStatus, String failureCode,
                        int detectionCount, List<String> warnings, LocalDate lastConfirmedDate,
                        Integer lastConfirmedCount) {
    }

    private final class AssistantRowMapper implements RowMapper<AssistantRow> {
        @Override
        public AssistantRow mapRow(ResultSet resultSet, int rowNumber) throws SQLException {
            byte[] sessionId = resultSet.getBytes("session_id");
            byte[] penId = resultSet.getBytes("pen_id");
            java.sql.Date lastDate = resultSet.getDate("last_confirmed_date");
            return new AssistantRow(
                    bytesToUuid(penId),
                    resultSet.getString("building_code"),
                    resultSet.getString("building_name"),
                    resultSet.getString("pen_code"),
                    resultSet.getString("pen_name"),
                    sessionId == null ? null : bytesToUuid(sessionId),
                    resultSet.getString("status"),
                    (Integer) resultSet.getObject("candidate_count"),
                    (Integer) resultSet.getObject("confirmed_count"),
                    resultSet.getString("inference_status"),
                    resultSet.getString("failure_code"),
                    resultSet.getInt("detection_count"),
                    parseWarnings(resultSet.getString("warnings_json")),
                    lastDate == null ? null : lastDate.toLocalDate(),
                    (Integer) resultSet.getObject("last_confirmed_count"));
        }
    }
}
