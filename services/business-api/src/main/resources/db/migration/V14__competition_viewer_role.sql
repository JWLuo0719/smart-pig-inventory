ALTER TABLE organization_membership DROP CHECK ck_membership_role;
ALTER TABLE organization_membership ADD COLUMN access_expires_at TIMESTAMP(6) NULL;
ALTER TABLE organization_membership ADD CONSTRAINT ck_membership_role CHECK (
    role_key IN ('OPERATOR', 'REVIEWER', 'FARM_ADMIN', 'SYSTEM_ADMIN', 'COMPETITION_VIEWER')
);
