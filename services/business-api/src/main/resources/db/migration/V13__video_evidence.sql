ALTER TABLE upload_package DROP CHECK ck_package_capture_kind;
ALTER TABLE upload_package ADD CONSTRAINT ck_package_capture_kind
    CHECK (capture_kind IN ('single', 'left_center_right', 'video'));
