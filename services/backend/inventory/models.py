import uuid

from django.conf import settings
from django.core.validators import MinValueValidator
from django.db import models


class TimeStampedModel(models.Model):
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        abstract = True


class FarmOrganization(TimeStampedModel):
    code = models.CharField(max_length=64, unique=True)
    name = models.CharField(max_length=128)
    is_active = models.BooleanField(default=True)
    erp_external_id = models.CharField(max_length=128, blank=True)
    sync_version = models.CharField(max_length=128, blank=True)

    class Meta:
        ordering = ["code"]
        verbose_name = "猪场组织"
        verbose_name_plural = verbose_name

    def __str__(self):
        return f"{self.code} {self.name}"


class OrganizationMembership(TimeStampedModel):
    class Role(models.TextChoices):
        OPERATOR = "operator", "现场操作员"
        REVIEWER = "reviewer", "审核员"
        ADMIN = "admin", "组织管理员"

    organization = models.ForeignKey(FarmOrganization, on_delete=models.CASCADE, related_name="memberships")
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="farm_memberships")
    role = models.CharField(max_length=16, choices=Role.choices, default=Role.OPERATOR)
    is_active = models.BooleanField(default=True)

    class Meta:
        constraints = [models.UniqueConstraint(fields=["organization", "user"], name="unique_user_membership_per_org")]
        verbose_name = "组织成员"
        verbose_name_plural = verbose_name


class Building(TimeStampedModel):
    organization = models.ForeignKey(FarmOrganization, on_delete=models.PROTECT, related_name="buildings")
    code = models.CharField(max_length=64)
    name = models.CharField(max_length=128)
    is_active = models.BooleanField(default=True)

    class Meta:
        ordering = ["organization__code", "code"]
        constraints = [models.UniqueConstraint(fields=["organization", "code"], name="unique_building_code_per_org")]
        verbose_name = "楼栋"
        verbose_name_plural = verbose_name

    def __str__(self):
        return f"{self.organization.code}/{self.code}"


class Pen(TimeStampedModel):
    building = models.ForeignKey(Building, on_delete=models.PROTECT, related_name="pens")
    code = models.CharField(max_length=64)
    name = models.CharField(max_length=128)
    is_active = models.BooleanField(default=True)
    capture_guidance = models.JSONField(default=dict, blank=True)

    class Meta:
        ordering = ["building__organization__code", "building__code", "code"]
        constraints = [models.UniqueConstraint(fields=["building", "code"], name="unique_pen_code_per_building")]
        verbose_name = "栏舍"
        verbose_name_plural = verbose_name

    def __str__(self):
        return f"{self.building}/{self.code}"


class InventoryCampaign(TimeStampedModel):
    class AggregationMethod(models.TextChoices):
        MEAN = "mean", "算术平均"

    organization = models.ForeignKey(FarmOrganization, on_delete=models.PROTECT, related_name="campaigns")
    name = models.CharField(max_length=128)
    start_date = models.DateField()
    end_date = models.DateField()
    aggregation_method = models.CharField(max_length=16, choices=AggregationMethod.choices, default=AggregationMethod.MEAN)
    is_closed = models.BooleanField(default=False)

    class Meta:
        verbose_name = "盘点周期"
        verbose_name_plural = verbose_name

    def __str__(self):
        return self.name


class InventorySession(TimeStampedModel):
    class Status(models.TextChoices):
        DRAFT = "draft", "草稿"
        SUBMITTED = "submitted", "已提交"
        PROCESSING = "processing", "推理中"
        REVIEW_REQUIRED = "review_required", "待人工复核"
        CONFIRMED = "confirmed", "已确认"
        FAILED = "failed", "失败"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    pen = models.ForeignKey(Pen, on_delete=models.PROTECT, related_name="inventory_sessions")
    campaign = models.ForeignKey(InventoryCampaign, on_delete=models.PROTECT, related_name="sessions", blank=True, null=True)
    business_date = models.DateField()
    status = models.CharField(max_length=24, choices=Status.choices, default=Status.DRAFT)
    created_by = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name="created_inventory_sessions")
    confirmed_by = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name="confirmed_inventory_sessions", blank=True, null=True)
    confirmed_at = models.DateTimeField(blank=True, null=True)
    manual_count = models.PositiveIntegerField(blank=True, null=True)
    note = models.TextField(blank=True)

    class Meta:
        ordering = ["-business_date", "pen__code"]
        verbose_name = "盘点任务"
        verbose_name_plural = verbose_name

    @property
    def organization(self):
        return self.pen.building.organization

    def __str__(self):
        return f"{self.pen} {self.business_date}"


class CaptureSet(TimeStampedModel):
    class Kind(models.TextChoices):
        SINGLE = "single", "单图"
        LEFT_CENTER_RIGHT = "left_center_right", "左中右三图"
        VIDEO = "video", "视频"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    session = models.ForeignKey(InventorySession, on_delete=models.PROTECT, related_name="capture_sets")
    kind = models.CharField(max_length=24, choices=Kind.choices)
    client_capture_id = models.UUIDField(unique=True)
    requires_manual_review = models.BooleanField(default=False)
    quality_flags = models.JSONField(default=list, blank=True)

    class Meta:
        verbose_name = "采集组"
        verbose_name_plural = verbose_name


class MediaAsset(TimeStampedModel):
    class ViewPosition(models.TextChoices):
        SINGLE = "single", "单图"
        LEFT = "left", "左"
        CENTER = "center", "中"
        RIGHT = "right", "右"
        VIDEO = "video", "视频"

    class State(models.TextChoices):
        ACTIVE = "active", "可用"
        LOCKED = "locked", "已锁定"
        DELETED = "deleted", "已删除"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    organization = models.ForeignKey(FarmOrganization, on_delete=models.PROTECT, related_name="media_assets")
    capture_set = models.ForeignKey(CaptureSet, on_delete=models.PROTECT, related_name="media_assets")
    view_position = models.CharField(max_length=12, choices=ViewPosition.choices)
    original_name = models.CharField(max_length=255)
    content_type = models.CharField(max_length=128)
    byte_size = models.PositiveBigIntegerField(validators=[MinValueValidator(1)])
    sha256 = models.CharField(max_length=64)
    perceptual_hash = models.CharField(max_length=128, blank=True)
    storage_key = models.CharField(max_length=512, unique=True)
    roi = models.JSONField(default=dict, blank=True)
    exif = models.JSONField(default=dict, blank=True)
    state = models.CharField(max_length=16, choices=State.choices, default=State.ACTIVE)
    deleted_at = models.DateTimeField(blank=True, null=True)

    class Meta:
        constraints = [models.UniqueConstraint(fields=["organization", "sha256"], name="unique_media_sha_per_organization")]
        verbose_name = "盘点媒体"
        verbose_name_plural = verbose_name


class UploadPackage(TimeStampedModel):
    class Status(models.TextChoices):
        AWAITING_BLOBS = "awaiting_blobs", "待上传文件"
        AWAITING_MANIFEST = "awaiting_manifest", "待上传清单"
        READY_TO_COMMIT = "ready_to_commit", "待提交"
        COMMITTED = "committed", "已提交"
        FAILED = "failed", "失败"

    id = models.UUIDField(primary_key=True, editable=False)
    session = models.ForeignKey(InventorySession, on_delete=models.PROTECT, related_name="upload_packages")
    idempotency_key = models.CharField(max_length=128)
    status = models.CharField(max_length=24, choices=Status.choices, default=Status.AWAITING_BLOBS)
    manifest = models.JSONField(blank=True, null=True)
    committed_at = models.DateTimeField(blank=True, null=True)

    class Meta:
        constraints = [models.UniqueConstraint(fields=["session", "idempotency_key"], name="unique_package_idempotency_key")]
        verbose_name = "上传包"
        verbose_name_plural = verbose_name


class UploadBlob(TimeStampedModel):
    package = models.ForeignKey(UploadPackage, on_delete=models.CASCADE, related_name="blobs")
    asset_id = models.UUIDField()
    relative_path = models.CharField(max_length=255)
    sha256 = models.CharField(max_length=64)
    byte_size = models.PositiveBigIntegerField(validators=[MinValueValidator(1)])
    content_type = models.CharField(max_length=128)
    uploaded_at = models.DateTimeField(blank=True, null=True)

    class Meta:
        constraints = [
            models.UniqueConstraint(fields=["package", "asset_id"], name="unique_blob_asset_per_package"),
            models.UniqueConstraint(fields=["package", "relative_path"], name="unique_blob_path_per_package"),
        ]


class InferenceJob(TimeStampedModel):
    class Status(models.TextChoices):
        QUEUED = "queued", "已排队"
        RUNNING = "running", "运行中"
        SUCCEEDED = "succeeded", "成功"
        REVIEW_REQUIRED = "review_required", "待复核"
        FAILED = "failed", "失败"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    session = models.ForeignKey(InventorySession, on_delete=models.PROTECT, related_name="inference_jobs")
    capture_set = models.ForeignKey(CaptureSet, on_delete=models.PROTECT, related_name="inference_jobs")
    status = models.CharField(max_length=24, choices=Status.choices, default=Status.QUEUED)
    provider_key = models.CharField(max_length=64)
    model_key = models.CharField(max_length=128, blank=True)
    model_version = models.CharField(max_length=128, blank=True)
    model_checksum = models.CharField(max_length=128, blank=True)
    adapter_version = models.CharField(max_length=64, default="v1")
    error_code = models.CharField(max_length=64, blank=True)
    error_detail = models.TextField(blank=True)
    latency_ms = models.PositiveIntegerField(blank=True, null=True)


class CountResult(TimeStampedModel):
    job = models.OneToOneField(InferenceJob, on_delete=models.PROTECT, related_name="result")
    raw_count = models.PositiveIntegerField()
    detections = models.JSONField(default=list, blank=True)
    quality_flags = models.JSONField(default=list, blank=True)
    is_final = models.BooleanField(default=False)


class AuditEvent(TimeStampedModel):
    class Action(models.TextChoices):
        MEDIA_DELETED = "media_deleted", "媒体删除"
        MEDIA_OVERRIDE = "media_override", "媒体管理员覆盖"
        COUNT_CONFIRMED = "count_confirmed", "数量确认"
        COUNT_CORRECTED = "count_corrected", "数量更正"
        ERP_SYNC = "erp_sync", "ERP 同步"
        PACKAGE_COMMITTED = "package_committed", "上传包提交"

    organization = models.ForeignKey(FarmOrganization, on_delete=models.PROTECT, related_name="audit_events")
    actor = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name="inventory_audit_events", blank=True, null=True)
    action = models.CharField(max_length=32, choices=Action.choices)
    target_type = models.CharField(max_length=64)
    target_id = models.CharField(max_length=64)
    reason = models.TextField(blank=True)
    payload = models.JSONField(default=dict, blank=True)

    class Meta:
        ordering = ["-created_at"]
        verbose_name = "审计事件"
        verbose_name_plural = verbose_name
