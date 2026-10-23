"use client";

import { FormEvent, useEffect, useRef, useState } from "react";
import { newIdempotencyKey } from "@/lib/authenticated-backend-client";
import { candidateDifference, reviewCommand, type ReviewMode } from "@/lib/review-command";
import { inventoryStatusLabel } from "@/lib/presentation-labels";

type ReviewSession = { id: string; version: number; count: number | null; rawModelCount: number | null; status: string };
export function ReviewCommandForm<T extends ReviewSession>({ session, mode, api, onReadback, onCancel }: {
  session: T; mode: ReviewMode; api: <R>(path: string, init?: RequestInit) => Promise<R>;
  onReadback: (session: T) => Promise<void>; onCancel: () => void;
}) {
  const [value, setValue] = useState(mode === "correction" ? session.count?.toString() ?? "" : "");
  const [reason, setReason] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const keys = useRef(new Map<string, string>());
  const active = useRef(true);
  useEffect(() => { active.current = true; return () => { active.current = false; }; }, []);
  async function submit(event: FormEvent) {
    event.preventDefault();
    if (submitting) return;
    setError(null);
    let command: ReturnType<typeof reviewCommand>;
    try { command = reviewCommand(mode, value, reason, session.rawModelCount); }
    catch (cause) { setError(cause instanceof Error ? cause.message : "请输入有效确认内容。"); return; }
    const intent = `${session.id}/${mode}/${command.intent}`;
    const key = keys.current.get(intent) ?? newIdempotencyKey();
    keys.current.set(intent, key);
    setSubmitting(true);
    try {
      const result = await api<T>(`inventory-sessions/${session.id}/${mode === "confirm" ? "confirm" : "corrections"}`, {
        method: "POST", headers: { "Content-Type": "application/json", "X-Idempotency-Key": key }, body: command.intent,
      });
      if (active.current) await onReadback(result);
    } catch (cause) {
      if (!active.current) return;
      // A response may be lost after commit. Read before offering the same-key retry.
      let status = "读取状态失败，请保留表单稍后重试";
      try {
        const current = await api<T>(`inventory-sessions/${session.id}`);
        status = `当前服务器状态：${inventoryStatusLabel(current.status)}，版本 v${current.version}，数量 ${current.count ?? "未知"}；请核对后再操作`;
      } catch { /* Keep the same pending intent and idempotency identity. */ }
      if (active.current) setError(`${cause instanceof Error ? cause.message : "提交结果不确定"}。${status}。相同内容重试沿用原幂等键。`);
    } finally { if (active.current) setSubmitting(false); }
  }
  return <form onSubmit={submit} className="review-command-form" aria-label={mode === "confirm" ? "人工确认表单" : "审计更正表单"}>
    <h3>{mode === "confirm" ? "核验原图后确认数量" : "创建新更正版本"}</h3>
    <p>服务端机器候选：{session.rawModelCount ?? "未知"}；当前值：{session.count ?? "未知"}；v{session.version}</p>
    <label>人工数量<input aria-label="人工数量" type="text" inputMode="numeric" value={value} onChange={(event) => setValue(event.target.value)} disabled={submitting} required /></label>
    <label>确认或更正依据<textarea aria-label="确认或更正依据" value={reason} onChange={(event) => setReason(event.target.value)} disabled={submitting} maxLength={500} /></label>
    <p aria-live="polite">人工数量与服务端候选差异：{candidateDifference(value, session.rawModelCount)}</p>
    <p>预览：{session.count ?? "未知"} → {value || "待输入"}；{mode === "correction" ? `创建 v${session.version + 1}，旧版本与证据保留` : "确认后锁定引用证据"}。</p>
    {error && <p role="alert" className="form-error">{error}</p>}
    <div><button className="primary-inline" type="submit" disabled={submitting}>{submitting ? "正在提交并核对…" : mode === "confirm" ? "提交人工确认" : "提交审计更正"}</button><button className="text-button" type="button" onClick={onCancel} disabled={submitting}>关闭表单</button></div>
  </form>;
}
