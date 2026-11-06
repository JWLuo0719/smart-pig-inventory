package com.smartfarm.inventory.inventory.infrastructure;

import java.nio.ByteBuffer;
import java.time.LocalDate;
import java.util.List;
import java.util.UUID;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

/** Read-only projections; no image, prompt text or internal inference detail crosses this boundary. */
@Repository
public class JdbcAssistantToolRepository {
    private final JdbcTemplate jdbc;
    public JdbcAssistantToolRepository(JdbcTemplate jdbc) { this.jdbc = jdbc; }

    public List<DayRow> day(UUID organization, LocalDate date) {
        return jdbc.query("""
                SELECT p.id AS pen_id, s.id AS session_id, s.status, s.confirmed_count, s.candidate_count
                FROM pen p JOIN building b ON b.id=p.building_id
                LEFT JOIN inventory_session s ON s.id=(
                  SELECT c.id FROM inventory_session c
                  WHERE c.pen_id=p.id AND c.business_date=? AND c.status<>'superseded'
                  ORDER BY (c.status='confirmed') DESC,c.updated_at DESC,c.created_at DESC,c.id DESC LIMIT 1)
                WHERE b.organization_id=? AND b.enabled=TRUE AND p.enabled=TRUE
                ORDER BY b.code,p.code,p.id
                """, (rs, n) -> new DayRow(uuid(rs.getBytes("pen_id")), uuid(rs.getBytes("session_id")),
                        rs.getString("status"), (Integer) rs.getObject("confirmed_count"),
                        (Integer) rs.getObject("candidate_count")), date, bytes(organization));
    }

    public boolean enabledPen(UUID organization, UUID pen) {
        Integer count = jdbc.queryForObject("""
                SELECT COUNT(*) FROM pen p JOIN building b ON b.id=p.building_id
                WHERE p.id=? AND b.organization_id=? AND p.enabled=TRUE AND b.enabled=TRUE
                """, Integer.class, bytes(pen), bytes(organization));
        return count != null && count == 1;
    }

    public List<HistoryRow> history(UUID organization, UUID pen, LocalDate from, LocalDate to) {
        return jdbc.query("""
                SELECT s.id,s.business_date,s.confirmed_count
                FROM inventory_session s JOIN pen p ON p.id=s.pen_id JOIN building b ON b.id=p.building_id
                WHERE b.organization_id=? AND p.id=? AND p.enabled=TRUE AND b.enabled=TRUE
                  AND s.status='confirmed' AND s.business_date BETWEEN ? AND ?
                ORDER BY s.business_date,s.id
                """, (rs, n) -> new HistoryRow(uuid(rs.getBytes("id")),
                        rs.getObject("business_date", LocalDate.class), (Integer) rs.getObject("confirmed_count")),
                bytes(organization), bytes(pen), from, to);
    }

    private byte[] bytes(UUID id) {
        return ByteBuffer.allocate(16).putLong(id.getMostSignificantBits()).putLong(id.getLeastSignificantBits()).array();
    }
    private UUID uuid(byte[] value) {
        return value == null ? null : new UUID(ByteBuffer.wrap(value).getLong(), ByteBuffer.wrap(value).getLong(8));
    }
    public record DayRow(UUID penId, UUID sessionId, String state, Integer confirmed, Integer candidate) {}
    public record HistoryRow(UUID sessionId, LocalDate date, Integer confirmed) {}
}
