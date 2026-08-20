type PenState = "confirmed" | "uploading" | "review" | "failed";

const pens: Array<{ code: string; building: string; count: string; detail: string; state: PenState }> = [
  { code: "08栏", building: "B02 育肥二栋", count: "126", detail: "08:42 已确认", state: "confirmed" },
  { code: "03栏", building: "B01 育肥一栋", count: "—", detail: "2/3 图片已上传", state: "uploading" },
  { code: "12栏", building: "B02 育肥二栋", count: "118?", detail: "疑似跨图重复", state: "review" },
  { code: "05栏", building: "B03 保育栋", count: "—", detail: "推理服务不可用", state: "failed" },
];

const labels: Record<PenState, string> = {
  confirmed: "已确认",
  uploading: "上传中",
  review: "需复核",
  failed: "失败",
};

export function FieldOverview() {
  return (
    <div className="workspace">
      <div className="prototype-notice" role="note">
        页面框架预览 · 以下栏舍、数量和时间均为演示数据，尚未连接业务 API
      </div>
      <section className="attention-strip" aria-labelledby="attention-title">
        <div>
          <span className="eyebrow">今天 · 08月18日</span>
          <h2 id="attention-title">先处理会阻塞盘点的事项</h2>
        </div>
        <div className="attention-counts">
          <a href="#review"><strong>7</strong><span>待复核</span></a>
          <a href="#upload"><strong>3</strong><span>上传中断</span></a>
          <a href="#model"><strong>1</strong><span>模型异常</span></a>
        </div>
      </section>

      <div className="content-grid">
        <section className="panel" aria-labelledby="pens-title">
          <div className="section-heading">
            <div><span className="eyebrow">栏舍门牌</span><h2 id="pens-title">最近作业栏舍</h2></div>
            <button type="button" className="text-button">查看全部</button>
          </div>
          <div className="pen-grid">
            {pens.map((pen) => (
              <article className={`pen-plate ${pen.state}`} key={`${pen.building}-${pen.code}`}>
                <div className="pen-rail" aria-hidden="true" />
                <div className="pen-head"><span>{pen.building}</span><strong>{pen.code}</strong></div>
                <div className="pen-body">
                  <span className="state-label">{labels[pen.state]}</span>
                  <div className="count"><strong>{pen.count}</strong><span>头</span></div>
                  <p>{pen.detail}</p>
                </div>
                <button type="button" aria-label={`打开 ${pen.building} ${pen.code}`}>打开栏舍 <span aria-hidden="true">→</span></button>
              </article>
            ))}
          </div>
        </section>

        <aside className="panel queue-panel" aria-labelledby="queue-title">
          <div className="section-heading">
            <div><span className="eyebrow">队列健康</span><h2 id="queue-title">上传与推理</h2></div>
          </div>
          <ol className="queue-list">
            <li><span className="queue-icon warning">!</span><div><strong>B01-03栏</strong><p>弱网中断，保留 1 个 Blob 待续传</p></div><time>2 分钟</time></li>
            <li><span className="queue-icon review">?</span><div><strong>B02-12栏</strong><p>三视图未启用自动去重，等待人工确认</p></div><time>8 分钟</time></li>
            <li><span className="queue-icon failed">×</span><div><strong>推理 Provider</strong><p>当前为 unavailable，不会生成模拟数量</p></div><time>当前</time></li>
          </ol>
          <button type="button" className="primary-button">进入失败任务</button>
        </aside>
      </div>

      <section className="panel progress-panel" aria-labelledby="progress-title">
        <div className="section-heading">
          <div><span className="eyebrow">任务轨道</span><h2 id="progress-title">今日盘点进度</h2></div>
          <span className="summary-number">18 / 42 栏</span>
        </div>
        <div className="progress-track" aria-label="今日盘点完成 43%"><span style={{ width: "43%" }} /></div>
        <div className="building-row"><strong>B01 育肥一栋</strong><span>8 / 16</span><small>1 个包待上传</small></div>
        <div className="building-row"><strong>B02 育肥二栋</strong><span>7 / 14</span><small>2 个结果待复核</small></div>
        <div className="building-row"><strong>B03 保育栋</strong><span>3 / 12</span><small>推理已降级</small></div>
      </section>
    </div>
  );
}
