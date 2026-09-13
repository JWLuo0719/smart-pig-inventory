package com.smartfarm.inventory.masterdata.application;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.smartfarm.inventory.inventory.application.InventoryException;
import com.smartfarm.inventory.inventory.infrastructure.SecurityReviewActor;
import com.smartfarm.inventory.masterdata.domain.MasterDataChanges.NamedEntity;
import com.smartfarm.inventory.masterdata.infrastructure.JdbcMasterDataRepository;
import java.nio.ByteBuffer;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class MasterDataAdministrationService {
    private final JdbcTemplate jdbc;
    private final JdbcMasterDataRepository repository;
    private final SecurityReviewActor actor;
    private final ObjectMapper mapper;

    public MasterDataAdministrationService(JdbcTemplate jdbc, JdbcMasterDataRepository repository,
            SecurityReviewActor actor, ObjectMapper mapper) {
        this.jdbc = jdbc; this.repository = repository; this.actor = actor; this.mapper = mapper;
    }

    public record Command(UUID parentId, String code, String name, boolean enabled, long expectedVersion, String reason) {
        public Command {
            code = normalize(code, 64); name = normalize(name, 128); reason = normalize(reason, 500);
            if (expectedVersion < 0) throw InventoryException.invalid("Invalid expected version");
        }
        private static String normalize(String value, int maximum) {
            if (value == null || value.strip().isEmpty() || value.strip().length() > maximum
                    || value.codePoints().anyMatch(Character::isISOControl)) {
                throw InventoryException.invalid("Code, name and reason must be non-empty bounded text");
            }
            return value.strip();
        }
    }

    @Transactional(isolation = org.springframework.transaction.annotation.Isolation.READ_COMMITTED)
    public NamedEntity save(String type, UUID id, UUID key, Command command, String correlationId) {
        String table = switch (type) {
            case "organizations" -> "farm_organization";
            case "buildings" -> "building";
            case "pens" -> "pen";
            default -> throw InventoryException.notFound();
        };
        UUID organization = actor.activeOrganizationId();
        actor.assertCanManageMasterData(organization);
        // One organization lock serializes both command replay and sync-version allocation.
        List<Boolean> locked = jdbc.query("SELECT enabled FROM farm_organization WHERE id = ? FOR UPDATE",
                (rs, n) -> rs.getBoolean(1), bytes(organization));
        if (locked.isEmpty()) throw InventoryException.notFound();
        String request = json(Map.of("type", type, "id", id, "command", command));
        var replay = jdbc.query("SELECT actor_id, request_json, response_json FROM master_data_command WHERE organization_id=? AND idempotency_key=?",
                (rs, n) -> List.of(rs.getString(1), rs.getString(2), rs.getString(3)), bytes(organization), bytes(key));
        if (!replay.isEmpty()) {
            var row = replay.getFirst();
            if (!row.getFirst().equals(actor.subjectId()) || !sameJson(row.get(1), request)) {
                throw InventoryException.conflict("Idempotency key already used for another command");
            }
            try { return mapper.readValue(row.get(2), NamedEntity.class); }
            catch (JsonProcessingException e) { throw new IllegalStateException("Cannot read master-data replay", e); }
        }
        List<NamedEntity> entities = switch (type) {
            case "organizations" -> repository.organizations(organization, null);
            case "buildings" -> repository.buildings(organization, null);
            default -> repository.pens(organization, null);
        };
        NamedEntity before = entities.stream().filter(e -> e.id().equals(id)).findFirst().orElse(null);
        if (before == null) {
            if (type.equals("organizations") || command.expectedVersion() != 0
                    || jdbc.queryForObject("SELECT COUNT(*) FROM " + table + " WHERE id=?", Integer.class, bytes(id)) != 0) {
                throw InventoryException.notFound();
            }
        } else if (before.syncVersion() != command.expectedVersion()) {
            throw InventoryException.conflict("Master data changed; reload before saving");
        }
        UUID expectedParent = type.equals("organizations") ? null
                : type.equals("buildings") ? organization : command.parentId();
        if (!java.util.Objects.equals(expectedParent, command.parentId())
                || (before != null && !java.util.Objects.equals(before.parentId(), command.parentId()))) {
            throw InventoryException.invalid("Parent cannot be changed");
        }
        if (type.equals("pens")) {
            NamedEntity parent = repository.buildings(organization, null).stream()
                    .filter(e -> e.id().equals(command.parentId())).findFirst().orElseThrow(InventoryException::notFound);
            if (command.enabled() && !parent.enabled()) throw InventoryException.conflict("Enable the building first");
        }
        if (!type.equals("organizations") && command.enabled() && !locked.getFirst()) {
            throw InventoryException.conflict("Enable the organization first");
        }
        if (!command.enabled()) {
            boolean hasEnabledChildren = type.equals("organizations")
                    ? repository.buildings(organization, null).stream().anyMatch(NamedEntity::enabled)
                    : type.equals("buildings") && repository.pens(organization, null).stream()
                        .anyMatch(p -> p.parentId().equals(id) && p.enabled());
            if (hasEnabledChildren) throw InventoryException.conflict("Disable child locations first");
        }
        long version = Math.addExact(repository.highWatermark(organization), 1);
        try {
            if (before == null) {
                String parentColumn = type.equals("buildings") ? "organization_id" : "building_id";
                jdbc.update("INSERT INTO " + table + " (id," + parentColumn + ",code,name,enabled,sync_version) VALUES (?,?,?,?,?,?)",
                        bytes(id), bytes(command.parentId()), command.code(), command.name(), command.enabled(), version);
            } else {
                jdbc.update("UPDATE " + table + " SET code=?,name=?,enabled=?,sync_version=? WHERE id=?",
                        command.code(), command.name(), command.enabled(), version, bytes(id));
            }
        } catch (DuplicateKeyException e) { throw InventoryException.conflict("This code is unavailable; choose another code"); }
        NamedEntity result = new NamedEntity(id, command.parentId(), command.code(), command.name(), command.enabled(),
                before == null ? null : before.erpExternalId(), version);
        jdbc.update("INSERT INTO master_data_command (organization_id,idempotency_key,actor_id,request_json,response_json) VALUES (?,?,?,CAST(? AS JSON),CAST(? AS JSON))",
                bytes(organization), bytes(key), actor.subjectId(), request, json(result));
        jdbc.update("INSERT INTO audit_event (id,organization_id,actor_id,action,target_type,target_id,reason,before_json,after_json,correlation_id) VALUES (?,?,?,?,?,?,?,CAST(? AS JSON),CAST(? AS JSON),?)",
                bytes(UUID.randomUUID()), bytes(organization), actor.subjectId(), "master_data.saved", type, id.toString(),
                command.reason(), json(before), json(result), correlationId);
        return result;
    }

    private String json(Object value) {
        try { return mapper.writeValueAsString(value); }
        catch (JsonProcessingException e) { throw new IllegalStateException("Cannot serialize master data", e); }
    }
    private boolean sameJson(String first, String second) {
        try { return mapper.readTree(first).equals(mapper.readTree(second)); }
        catch (JsonProcessingException e) { throw new IllegalStateException("Cannot compare master data", e); }
    }
    private static byte[] bytes(UUID value) {
        return ByteBuffer.allocate(16).putLong(value.getMostSignificantBits()).putLong(value.getLeastSignificantBits()).array();
    }
}
