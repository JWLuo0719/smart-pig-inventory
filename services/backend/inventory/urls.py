from django.urls import include, path
from rest_framework.routers import DefaultRouter

from .views import (
    BuildingViewSet, CampaignReportView, CampaignViewSet, DailyReportView, InventorySessionViewSet,
    MediaAssetViewSet, MockErpSyncView, OrganizationViewSet, PenViewSet, UploadBlobView,
    UploadCommitView, UploadManifestView, UploadPackageCreateView,
)

router = DefaultRouter()
router.register("organizations", OrganizationViewSet, basename="organization")
router.register("buildings", BuildingViewSet, basename="building")
router.register("pens", PenViewSet, basename="pen")
router.register("campaigns", CampaignViewSet, basename="campaign")
router.register("sessions", InventorySessionViewSet, basename="session")
router.register("media", MediaAssetViewSet, basename="media")

urlpatterns = [
    path("", include(router.urls)),
    path("packages/", UploadPackageCreateView.as_view()),
    path("packages/<uuid:package_id>/blobs/<uuid:asset_id>/", UploadBlobView.as_view()),
    path("packages/<uuid:package_id>/manifest/", UploadManifestView.as_view()),
    path("packages/<uuid:package_id>/commit/", UploadCommitView.as_view()),
    path("reports/daily/", DailyReportView.as_view()),
    path("reports/campaigns/<int:campaign_id>/", CampaignReportView.as_view()),
    path("erp/mock-sync/", MockErpSyncView.as_view()),
]

