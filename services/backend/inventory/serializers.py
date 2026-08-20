from rest_framework import serializers

from .models import (
    Building, CaptureSet, CountResult, FarmOrganization, InferenceJob, InventoryCampaign,
    InventorySession, MediaAsset, Pen, UploadBlob, UploadPackage,
)


class FarmOrganizationSerializer(serializers.ModelSerializer):
    class Meta:
        model = FarmOrganization
        fields = ("id", "code", "name", "is_active", "erp_external_id", "sync_version", "updated_at")


class BuildingSerializer(serializers.ModelSerializer):
    class Meta:
        model = Building
        fields = ("id", "organization", "code", "name", "is_active", "updated_at")


class PenSerializer(serializers.ModelSerializer):
    organization_id = serializers.IntegerField(source="building.organization_id", read_only=True)

    class Meta:
        model = Pen
        fields = ("id", "building", "organization_id", "code", "name", "is_active", "capture_guidance", "updated_at")


class InventoryCampaignSerializer(serializers.ModelSerializer):
    class Meta:
        model = InventoryCampaign
        fields = ("id", "organization", "name", "start_date", "end_date", "aggregation_method", "is_closed")


class InventorySessionSerializer(serializers.ModelSerializer):
    pen_code = serializers.CharField(source="pen.code", read_only=True)
    organization_id = serializers.IntegerField(source="pen.building.organization_id", read_only=True)
    result_count = serializers.SerializerMethodField()

    class Meta:
        model = InventorySession
        fields = (
            "id", "pen", "pen_code", "organization_id", "campaign", "business_date", "status",
            "created_by", "confirmed_by", "confirmed_at", "manual_count", "note", "result_count",
            "created_at", "updated_at",
        )
        read_only_fields = ("created_by", "confirmed_by", "confirmed_at", "status")

    def get_result_count(self, obj):
        latest = obj.inference_jobs.filter(status=InferenceJob.Status.SUCCEEDED).order_by("-created_at").first()
        return latest.result.raw_count if latest and hasattr(latest, "result") else None


class UploadBlobSerializer(serializers.ModelSerializer):
    class Meta:
        model = UploadBlob
        fields = ("asset_id", "relative_path", "sha256", "byte_size", "content_type", "uploaded_at")


class UploadPackageSerializer(serializers.ModelSerializer):
    blobs = UploadBlobSerializer(many=True, read_only=True)

    class Meta:
        model = UploadPackage
        fields = ("id", "session", "idempotency_key", "status", "manifest", "committed_at", "blobs", "created_at")
        read_only_fields = ("status", "manifest", "committed_at")


class MediaAssetSerializer(serializers.ModelSerializer):
    class Meta:
        model = MediaAsset
        fields = (
            "id", "capture_set", "view_position", "original_name", "content_type", "byte_size", "sha256",
            "perceptual_hash", "storage_key", "roi", "exif", "state", "created_at",
        )
        read_only_fields = ("storage_key", "sha256", "perceptual_hash", "state")


class CountResultSerializer(serializers.ModelSerializer):
    class Meta:
        model = CountResult
        fields = ("raw_count", "detections", "quality_flags", "is_final", "created_at")


class InferenceJobSerializer(serializers.ModelSerializer):
    result = CountResultSerializer(read_only=True)

    class Meta:
        model = InferenceJob
        fields = (
            "id", "session", "capture_set", "status", "provider_key", "model_key", "model_version",
            "model_checksum", "adapter_version", "error_code", "error_detail", "latency_ms", "result",
            "created_at", "updated_at",
        )

