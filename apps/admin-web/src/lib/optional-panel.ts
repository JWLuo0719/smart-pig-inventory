import { BackendApiError } from "./authenticated-backend-client.ts";

export type PanelName = "duplicates" | "failedJobs" | "audit";
export type PanelUser = { activeOrganizationId: string; memberships: { organizationId: string; roles: string[] }[] };
export type PanelState<T> =
  | { status: "loading" | "forbidden" }
  | { status: "error"; message: string }
  | { status: "ready"; data: T[] };

// Presentation only; the backend remains the authorization authority.
export function canReadPanel(user: PanelUser, panel: PanelName): boolean {
  const roles = user.memberships.filter((membership) => membership.organizationId === user.activeOrganizationId)
    .flatMap((membership) => membership.roles);
  return roles.some((role) => role === "FARM_ADMIN" || role === "SYSTEM_ADMIN" || (panel === "duplicates" && role === "REVIEWER"));
}

export function panelCount<T>(state: PanelState<T>): number | null {
  return state.status === "ready" ? state.data.length : null;
}

export async function loadOptionalPanel<T>(allowed: boolean, fetchRows: () => Promise<T[]>): Promise<PanelState<T>> {
  if (!allowed) return { status: "forbidden" };
  try {
    const data = await fetchRows();
    if (!Array.isArray(data)) throw new Error("Invalid list response");
    return { status: "ready", data };
  } catch (cause) {
    if (cause instanceof BackendApiError && cause.status === 403) return { status: "forbidden" };
    // A 404 may be authorization masking OR a missing route, never assume empty/denied.
    const message = cause instanceof BackendApiError ? `加载失败（HTTP ${cause.status}），请刷新重试。` : "加载失败，网络或响应异常，请刷新重试。";
    return { status: "error", message };
  }
}
