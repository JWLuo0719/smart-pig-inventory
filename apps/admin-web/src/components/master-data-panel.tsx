"use client";

import { useCallback, useEffect, useRef, useState, type FormEvent } from "react";
import { newIdempotencyKey } from "@/lib/authenticated-backend-client";

type Entity = { id: string; parentId: string | null; code: string; name: string; enabled: boolean; syncVersion: number };
type Changes = { organizations: Entity[]; buildings: Entity[]; pens: Entity[] };
type Kind = keyof Changes;
type Api = <T>(path: string, init?: RequestInit) => Promise<T>;
type Editing = { kind: Kind; entity: Entity; reason: string };
const titles = { organizations: "猪场", buildings: "栋舍", pens: "栏舍" };

export function MasterDataPanel({ api, organizationId, canManage }: { api: Api; organizationId: string; canManage: boolean }) {
  const [data, setData] = useState<Changes | null>(null);
  const [editing, setEditing] = useState<Editing | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const generation = useRef(0);
  const pending = useRef<{ body: string; path: string; key: string } | null>(null);
  const load = useCallback(async () => {
    const current = ++generation.current;
    setLoading(true); setData(null); setError(null);
    try {
      const next = await api<Changes>("master-data/changes");
      if (generation.current === current) setData(next);
    } catch { if (generation.current === current) setError("无法读取猪场资料，请刷新重试。"); }
    finally { if (generation.current === current) setLoading(false); }
  }, [api]);
  useEffect(() => {
    let cancelled = false;
    api<Changes>("master-data/changes")
      .then(next => { if (!cancelled) setData(next); })
      .catch(() => { if (!cancelled) setError("无法读取猪场资料，请刷新重试。"); })
      .finally(() => { if (!cancelled) setLoading(false); });
    return () => { cancelled = true; };
  }, [api, organizationId]);
  function begin(kind: Kind, entity?: Entity) {
    setNotice(null); setError(null); pending.current = null;
    setEditing({ kind, reason: "", entity: entity ?? { id: newIdempotencyKey(), parentId: kind === "buildings" ? organizationId : data?.buildings.find(b => b.enabled)?.id ?? null, code: "", name: "", enabled: true, syncVersion: 0 } });
  }
  async function save(event: FormEvent) {
    event.preventDefault(); if (!editing || saving) return;
    const { kind, entity, reason } = editing;
    const body = JSON.stringify({ parentId: entity.parentId, code: entity.code.trim(), name: entity.name.trim(), enabled: entity.enabled, expectedVersion: entity.syncVersion, reason: reason.trim() });
    const path = `master-data/${kind}/${entity.id}`;
    if (!pending.current || pending.current.body !== body || pending.current.path !== path) pending.current = { body, path, key: newIdempotencyKey() };
    setSaving(true); setError(null); setNotice(null);
    try {
      await api<Entity>(path, { method: "PUT", headers: { "Content-Type": "application/json", "X-Idempotency-Key": pending.current.key }, body });
      setEditing(null); pending.current = null; await load();
      setNotice("已保存并记录审计；手机同步主数据后可使用。");
    } catch { setError("保存未完成：检查编码是否重复、版本是否已更新；停用父级前先停用子级。网络恢复后可原样重试，或取消后刷新资料。"); }
    finally { setSaving(false); }
  }
  return <section id="master-data" className="panel" aria-labelledby="master-data-title">
    <div className="section-heading"><div><span className="eyebrow">猪场资料</span><h2 id="master-data-title">猪场、栋舍与栏舍</h2></div><button className="text-button" disabled={loading || saving || editing !== null} onClick={() => void load()}>刷新资料</button></div>
    <p>编码和名称用于现场选栏。停用保留历史盘点，编辑不会移动原有证据。</p>
    {error ? <p role="alert" className="form-error">{error}</p> : null}
    {notice ? <p role="status">{notice}</p> : null}
    {loading ? <p role="status">正在读取猪场资料…</p> : data ? <>
      {(["organizations", "buildings", "pens"] as Kind[]).map(kind => <div key={kind}>
        <h3>{titles[kind]}</h3>
        {canManage && kind !== "organizations" ? <button className="text-button" disabled={saving || editing !== null || (kind === "pens" && !data.buildings.some(b => b.enabled))} onClick={() => begin(kind)}>新增{titles[kind]}</button> : null}
        {data[kind].length === 0 ? <p>暂无{titles[kind]}资料。</p> : <ul className="report-list">{data[kind].map(entity => <li key={entity.id}><span>{kind === "pens" ? `${data.buildings.find(b => b.id === entity.parentId)?.code ?? ""} / ` : ""}{entity.code} · {entity.name} · {entity.enabled ? "启用" : "停用"}</span>{canManage ? <button className="text-button" disabled={saving || editing !== null} onClick={() => begin(kind, entity)}>编辑{titles[kind]} {entity.code}</button> : null}</li>)}</ul>}
      </div>)}
    </> : null}
    {editing ? <form className="login-form" onSubmit={save} aria-label={`维护${titles[editing.kind]}`}>
      <h3>{editing.entity.syncVersion === 0 ? "新增" : "编辑"}{titles[editing.kind]}</h3>
      {editing.kind === "pens" && editing.entity.syncVersion === 0 ? <label>所属栋舍<select required disabled={saving} value={editing.entity.parentId ?? ""} onChange={e => setEditing({ ...editing, entity: { ...editing.entity, parentId: e.target.value } })}>{data?.buildings.filter(b => b.enabled).map(b => <option key={b.id} value={b.id}>{b.code} · {b.name}</option>)}</select></label> : null}
      <label>编码<input required maxLength={64} disabled={saving} value={editing.entity.code} onChange={e => setEditing({ ...editing, entity: { ...editing.entity, code: e.target.value } })} /></label>
      <label>名称<input required maxLength={128} disabled={saving} value={editing.entity.name} onChange={e => setEditing({ ...editing, entity: { ...editing.entity, name: e.target.value } })} /></label>
      <label>状态<select disabled={saving} value={String(editing.entity.enabled)} onChange={e => setEditing({ ...editing, entity: { ...editing.entity, enabled: e.target.value === "true" } })}><option value="true">启用</option><option value="false">停用（保留历史）</option></select></label>
      <label>变更原因<input required maxLength={500} disabled={saving} value={editing.reason} onChange={e => setEditing({ ...editing, reason: e.target.value })} /></label>
      <button type="submit" className="primary-button" disabled={saving}>{saving ? "保存中…" : "保存资料"}</button>
      <button type="button" disabled={saving} onClick={() => { setEditing(null); pending.current = null; }}>取消编辑</button>
    </form> : null}
  </section>;
}
