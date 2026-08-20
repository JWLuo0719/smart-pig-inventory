from dataclasses import dataclass
from typing import Protocol


@dataclass(frozen=True)
class ErpOrganization:
    external_id: str
    code: str
    name: str
    version: str = ""


class ErpOrganizationProvider(Protocol):
    key: str

    def list_organizations(self) -> list[ErpOrganization]: ...


class MockErpOrganizationProvider:
    """Safe placeholder until Kingdee credentials and field mapping are supplied."""

    key = "mock"

    def list_organizations(self) -> list[ErpOrganization]:
        return []

