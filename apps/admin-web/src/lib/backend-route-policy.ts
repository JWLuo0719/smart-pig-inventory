const postRoutes = [
  /^auth\/(login|refresh|logout)$/,
  /^inventory-sessions\/[^/]+\/confirm$/,
  /^inventory-sessions\/[^/]+\/corrections$/,
  /^review\/near-duplicates\/[^/]+\/resolve$/,
  /^inference-jobs\/[^/]+\/retries$/,
  /^media-assets\/[^/]+\/override-delete$/,
];

const getRoutes = [
  /^master-data\/changes$/,
  /^media-assets$/,
  /^me$/,
  /^inventory-tasks$/,
  /^review\/near-duplicates$/,
  /^inventory-reports\/(daily|aggregate)$/,
  /^inventory-reports\/exports\/(pdf|xlsx)$/,
  /^audit-events$/,
  /^inference-jobs\/failed$/,
  /^inventory-sessions\/[^/]+$/,
  /^inventory-sessions\/[^/]+\/media$/,
  /^media-assets\/[^/]+\/content$/,
];

export function isPermittedBackendRoute(method: string, route: string): boolean {
  const patterns = method === "POST" ? postRoutes : method === "GET" ? getRoutes : method === "DELETE" ? [/^media-assets\/[^/]+$/] : method === "PUT" ? [/^master-data\/(organizations|buildings|pens)\/[0-9a-fA-F-]{36}$/] : [];
  return patterns.some((pattern) => pattern.test(route));
}
