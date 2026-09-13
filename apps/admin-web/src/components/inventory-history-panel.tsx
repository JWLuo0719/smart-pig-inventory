"use client";

import { useState, type FormEvent } from "react";
type Api = <T>(path: string, init?: RequestInit) => Promise<T>;
type Task = { penId: string; buildingCode: string; penCode: string; sessionId: string | null; status: string; confirmedCount: number | null };
type Daily = { sessionId: string; buildingCode: string; penCode: string; confirmedCount: number };
type Aggregate = { rawMean: number | null; roundedCount: number | null; includedDates: string[] };

export function InventoryHistoryPanel({ api, openSession }: { api: Api; openSession: (id: string) => Promise<void> }) {
  const [from, setFrom] = useState(() => new Date().toLocaleDateString("en-CA"));
  const [to, setTo] = useState(from);
  const [pen, setPen] = useState("");
  const [tasks, setTasks] = useState<Task[] | null>(null);
  const [penOptions, setPenOptions] = useState<Task[]>([]);
  const [daily, setDaily] = useState<Daily[] | null>(null);
  const [aggregate, setAggregate] = useState<Aggregate | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  async function query(event: FormEvent) {
    event.preventDefault(); if (loading) return;
    setLoading(true); setError(null); setTasks(null); setDaily(null); setAggregate(null);
    try {
      const [taskRows, dailyRows, summary] = await Promise.all([
        api<Task[]>(`inventory-tasks?businessDate=${encodeURIComponent(to)}`),
        api<Daily[]>(`inventory-reports/daily?businessDate=${encodeURIComponent(to)}`),
        pen ? api<Aggregate>(`inventory-reports/aggregate?penId=${encodeURIComponent(pen)}&from=${encodeURIComponent(from)}&to=${encodeURIComponent(to)}`) : Promise.resolve(null),
      ]);
      setTasks(taskRows); setPenOptions(taskRows); setDaily(dailyRows); setAggregate(summary);
    } catch { setError("无法读取历史盘点，请检查日期范围并重新查询。"); }
    finally { setLoading(false); }
  }
  return <section className="panel" id="inventory-history" aria-labelledby="inventory-history-title">
    <h2 id="inventory-history-title">历史日报与跨日综合盘点</h2>
    <p>日报与任务按结束日期查询；综合盘点只对所选栏舍范围内的已确认日期取平均。</p>
    <form className="report-export-controls" onSubmit={query}>
      <label>综合开始日期<input type="date" required max={to} value={from} disabled={loading} onChange={e => { setFrom(e.target.value); setAggregate(null); }} /></label>
      <label>查询日期 / 综合结束日期<input type="date" required min={from} value={to} disabled={loading} onChange={e => { setTo(e.target.value); setAggregate(null); setDaily(null); setTasks(null); }} /></label>
      <label>综合栏舍<select value={pen} disabled={loading} onChange={e => { setPen(e.target.value); setAggregate(null); }}><option value="">先查询日期，再选择栏舍</option>{penOptions.map(t => <option key={t.penId} value={t.penId}>{t.buildingCode} / {t.penCode}</option>)}</select></label>
      <button type="submit" className="primary-inline" disabled={loading}>{loading ? "查询中…" : "查询历史盘点"}</button>
    </form>
    {error ? <p role="alert" className="form-error">{error}</p> : null}
    {aggregate ? <p role="status">原始均值 {aggregate.rawMean ?? "—"}；展示数量 {aggregate.roundedCount ?? "—"} 头；参与日期 {aggregate.includedDates.join("、") || "无已确认样本"}</p> : null}
    {daily ? <><h3>已确认日报</h3><ul className="report-list">{daily.map(row => <li key={row.sessionId}><span>{row.buildingCode} / {row.penCode} · {row.confirmedCount} 头</span><button className="text-button" onClick={() => void openSession(row.sessionId)}>查看确认记录</button></li>)}</ul>{daily.length === 0 ? <p>该日期暂无已确认记录。</p> : null}</> : null}
    {tasks ? <><h3>该日期栏舍任务</h3><ul className="report-list">{tasks.map(row => <li key={row.penId}><span>{row.buildingCode} / {row.penCode} · {row.status} · {row.confirmedCount ?? "—"} 头</span>{row.sessionId ? <button className="text-button" onClick={() => void openSession(row.sessionId!)}>查看历史会话</button> : null}</li>)}</ul></> : null}
  </section>;
}
