export type EvidenceRef = { kind: "session" | "daily_report"; id: string | null; businessDate: string };
export type ToolFact = { tool: string; status: string; generatedAt: string; data: Record<string, unknown> | null; evidence: EvidenceRef[] };
export type AgentReply = {
  requestId: string; status: "ok" | "insufficient_evidence" | "answer_rejected" | "model_unavailable" | "limit_reached";
  answer: string | null; facts: ToolFact[]; evidence: EvidenceRef[]; model: string; promptVersion: string; elapsedMs: number; toolCalls: number;
};
export type ChatTurn = { role: "user" | "assistant"; content: string };

export const samplePrompts = [
  "请检查所选盘点：AI候选数和人工确认数分别是什么？还需要核对什么？",
  "所选业务日还有哪些栏舍没完成盘点或需要复核？分别下一步做什么？",
  "比较所选栏舍最近7天的确认数量；能直接解释成猪只减少吗？",
] as const;

export function agentStateLabel(state: string): string {
  return ({ ok: "依据已取得，可查看解释", insufficient_evidence: "证据不足，请补充日期或记录", answer_rejected: "解释未通过核对，请以事实卡为准", model_unavailable: "模型暂不可用，已取得的事实保留", limit_reached: "本次处理已达上限，请缩小问题重试" } as Record<string, string>)[state] ?? "结果状态未知";
}

export function displayCount(value: unknown): string {
  return typeof value === "number" && Number.isSafeInteger(value) && value >= 0 ? value.toString() : "未知";
}

export function evidencePath(value: EvidenceRef): string | null {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value.businessDate)) return null;
  if (value.kind === "session" && typeof value.id === "string" && /^[0-9a-f-]{36}$/i.test(value.id)) return `inventory-sessions/${encodeURIComponent(value.id)}`;
  return value.kind === "daily_report" && value.id === null ? `inventory-reports/daily?businessDate=${encodeURIComponent(value.businessDate)}` : null;
}

/** One generation for the chosen account/date/pen/session. Old JSON bodies cannot reappear after reset. */
export class AssistantRequestScope {
  private generation = 0;
  private controller: AbortController | null = null;
  reset(): void { this.generation++; this.controller?.abort(); this.controller = null; }
  start(): { signal: AbortSignal; current: () => boolean } {
    this.reset();
    const generation = this.generation;
    const controller = new AbortController(); this.controller = controller;
    return { signal: controller.signal, current: () => generation === this.generation && !controller.signal.aborted };
  }
}

export function parseReply(value: unknown): AgentReply {
  if (value === null || typeof value !== "object") throw new Error("无法读取回答，请重新查询。");
  const reply = value as AgentReply;
  if (!["ok", "insufficient_evidence", "answer_rejected", "model_unavailable", "limit_reached"].includes(reply.status)
      || !(reply.answer === null || typeof reply.answer === "string") || !Array.isArray(reply.facts)
      || !Array.isArray(reply.evidence) || reply.evidence.length > 50 || reply.facts.length > 6
      || typeof reply.requestId !== "string" || typeof reply.model !== "string" || typeof reply.promptVersion !== "string"
      || typeof reply.elapsedMs !== "number" || !Number.isFinite(reply.elapsedMs) || reply.elapsedMs < 0
      || !Number.isSafeInteger(reply.toolCalls) || reply.toolCalls < 0 || reply.toolCalls > 6) throw new Error("回答不符合预期格式，请重试。");
  const isCount = (item: unknown) => item === null || (typeof item === "number" && Number.isSafeInteger(item) && item >= 0);
  const isRecord = (item: unknown): item is Record<string, unknown> => item !== null && typeof item === "object" && !Array.isArray(item);
  if (reply.evidence.some(item => !isRecord(item) || evidencePath(item as EvidenceRef) === null)) throw new Error("来源引用格式异常。");
  for (const fact of reply.facts) {
    if (!fact || typeof fact.tool !== "string" || typeof fact.status !== "string"
        || (fact.data !== null && (typeof fact.data !== "object" || Array.isArray(fact.data)))) throw new Error("事实数据格式异常。");
    if (fact.status !== "ok" || !fact.data) continue;
    const data = fact.data;
    if (fact.tool === "inspect_session" && (!isCount(data.confirmedCount) || !isCount(data.candidateCount) || typeof data.state !== "string")) throw new Error("数量事实格式异常。");
    if (fact.tool === "get_day_overview" && (!Array.isArray(data.rows) || data.rows.length > 50 || typeof data.hasMore !== "boolean"
        || !isCount(data.confirmedHeads) || !isCount(data.scopePenCount) || !isCount(data.confirmedPenCount)
        || data.rows.some(row => !isRecord(row) || typeof row.penId !== "string" || typeof row.state !== "string" || !isCount(row.confirmedCount) || !isCount(row.candidateCount)))) throw new Error("概况事实格式异常。");
    if (fact.tool === "get_pen_history" && (!Array.isArray(data.points) || data.points.length > 90
        || data.points.some(point => !isRecord(point) || typeof point.date !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(point.date) || !isCount(point.confirmedCount)))) throw new Error("历史事实格式异常。");
  }
  return reply;
}
