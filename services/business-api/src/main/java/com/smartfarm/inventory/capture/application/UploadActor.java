package com.smartfarm.inventory.capture.application;

import java.util.UUID;

public interface UploadActor {
    void assertCanAccess(UUID organizationId);

    String subjectId();
}
