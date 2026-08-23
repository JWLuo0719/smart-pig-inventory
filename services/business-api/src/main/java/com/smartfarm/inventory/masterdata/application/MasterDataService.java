package com.smartfarm.inventory.masterdata.application;

import com.smartfarm.inventory.masterdata.domain.MasterDataChanges;
import com.smartfarm.inventory.masterdata.infrastructure.JdbcMasterDataRepository;
import java.util.UUID;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class MasterDataService {
    private final JdbcMasterDataRepository repository;

    public MasterDataService(JdbcMasterDataRepository repository) {
        this.repository = repository;
    }

    @Transactional(readOnly = true)
    public MasterDataChanges changes(UUID activeOrganizationId, String cursor) {
        long highWatermark = repository.highWatermark(activeOrganizationId);
        Long requestedCursor = parseCursor(cursor);
        boolean fullResyncRequired = requestedCursor == null || requestedCursor > highWatermark;
        Long afterVersion = fullResyncRequired ? null : requestedCursor;
        return new MasterDataChanges(
                Long.toString(highWatermark),
                fullResyncRequired,
                repository.organizations(activeOrganizationId, afterVersion),
                repository.buildings(activeOrganizationId, afterVersion),
                repository.pens(activeOrganizationId, afterVersion),
                repository.tombstones(activeOrganizationId, afterVersion));
    }

    private Long parseCursor(String cursor) {
        if (cursor == null || cursor.isBlank()) {
            return null;
        }
        try {
            long value = Long.parseLong(cursor);
            return value < 0 ? null : value;
        } catch (NumberFormatException exception) {
            return null;
        }
    }
}
