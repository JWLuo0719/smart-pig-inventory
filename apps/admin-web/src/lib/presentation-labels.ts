const inventoryStatuses: Record<string, string> = {
  pending: "待采集", draft: "草稿", submitted: "已提交", processing: "处理中",
  review_required: "待复核", confirmed: "已确认", superseded: "历史版本",
};
const evidenceStates: Record<string, string> = {
  staged: "待提交", uploaded: "已上传", submitted: "已提交", locked: "已锁定", deleted: "已删除",
};
const directions: Record<string, string> = { single: "单图", left: "左图", center: "中图", right: "右图" };
const inferenceSources: Record<string, string> = { manual: "人工", device: "设备端", server: "服务端" };

export function inventoryStatusLabel(status: string): string { return inventoryStatuses[status] ?? "状态未知"; }
export function evidenceStateLabel(state: string): string { return evidenceStates[state] ?? "状态未知"; }
export function directionLabel(direction: string): string { return directions[direction] ?? "方向未知"; }
export function inferenceSourceLabel(source: string | null): string { return source === null ? "未知" : inferenceSources[source] ?? "未知"; }
