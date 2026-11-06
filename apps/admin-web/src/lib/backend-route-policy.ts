const postRoutes = [
  /^assistant\/chat$/,
  /^assistant\/tools\/(get-day-overview|get-pen-history)$/,
  /^assistant\/tools\/inspect-session$/,
  /^auth\/(login|refresh|logout)$/,
  /^inventory-sessions\/[^/]+\/confirm$/,
  /^inventory-sessions\/[^/]+\/corrections$/,
  /^review\/near-duplicates\/[^/]+\/resolve$/,
  /^inference-jobs\/[^/]+\/retries$/,
  /^media-assets\/[^/]+\/override-delete$/,
];

const getRoutes = [
  /^assistant\/status$/,
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
  /^inventory-sessions\/[^/]+\/versions$/,
  /^media-assets\/[^/]+\/content$/,
  /^media-assets\/[^/]+\/thumbnail$/,
];

export function isPermittedBackendRoute(method: string, route: string): boolean {
  const patterns = method === "POST" ? postRoutes : method === "GET" ? getRoutes : method === "DELETE" ? [/^media-assets\/[^/]+$/] : method === "PUT" ? [/^master-data\/(organizations|buildings|pens)\/[0-9a-fA-F-]{36}$/] : [];
  return patterns.some((pattern) => pattern.test(route));
}
