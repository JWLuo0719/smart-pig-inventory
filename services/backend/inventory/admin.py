from django.contrib import admin

from .models import (
    AuditEvent, Building, CaptureSet, CountResult, FarmOrganization, InferenceJob,
    InventoryCampaign, InventorySession, MediaAsset, OrganizationMembership, Pen, UploadBlob, UploadPackage,
)


@admin.register(FarmOrganization)
class FarmOrganizationAdmin(admin.ModelAdmin):
    list_display = ("code", "name", "is_active", "erp_external_id", "sync_version")
    search_fields = ("code", "name", "erp_external_id")


@admin.register(Building)
class BuildingAdmin(admin.ModelAdmin):
    list_display = ("organization", "code", "name", "is_active")
    list_filter = ("organization", "is_active")


@admin.register(Pen)
class PenAdmin(admin.ModelAdmin):
    list_display = ("building", "code", "name", "is_active")
    list_filter = ("building__organization", "is_active")


@admin.register(InventorySession)
class InventorySessionAdmin(admin.ModelAdmin):
    list_display = ("id", "pen", "business_date", "status", "manual_count", "confirmed_at")
    list_filter = ("status", "business_date", "pen__building__organization")
    search_fields = ("pen__code",)


for model in (OrganizationMembership, InventoryCampaign, CaptureSet, MediaAsset, UploadPackage, UploadBlob, InferenceJob, CountResult, AuditEvent):
    admin.site.register(model)
