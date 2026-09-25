"""弱网重放 / 契约探针 CLI（按 App 的真实 4 步上传合同）。

用法：

  # 1) 契约探针：目标服务实现了哪些合同端点（只读探测，不写数据）
  python tools/run_app_replay.py --base http://127.0.0.1:8787 --probe-only

  # 2) 弱网重放：注入断网/超时/响应丢失/5xx/401，验证幂等与续传
  python tools/run_app_replay.py --base https://pig-inventory.local:8443 \
      --username <账号> --password <口令> --profile flaky --packages 3

  # 3) 全部场景 + 报告落盘
  python tools/run_app_replay.py --base <url> --username u --password p \
      --profile all --report test-assets/app-replay-report.md

  # 4) 针对本仓库 Agent 后端（不是 App 合同，用于对照差异）
  python tools/run_app_replay.py --base http://127.0.0.1:8787 --probe-only

退出码：0 = 全部不变量满足；1 = 有失败；2 = 目标不可达/参数问题。
"""
from __future__ import annotations

import argparse
import json
import random
import sys
import uuid
from datetime import date, datetime, timezone
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[1]
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

from tools.app_contract_sim import (  # noqa: E402
    PROFILES,
    Asset,
    CapturePackage,
    ContractClient,
    NetworkFault,
    PackageSynchronizer,
    jpeg_bytes,
    probe_contract,
    verify,
)


def build_package(index: int, args) -> CapturePackage:
    """构造一个采集包：App 侧 identity 都是 UUID。"""
    assets = []
    for view in range(args.assets_per_package):
        view_position = ("single", "left", "center", "right")[min(view, 3)]
        assets.append(
            Asset(
                asset_id=str(uuid.uuid4()),
                data=jpeg_bytes(index * 10 + view),
                view_position=view_position,
                original_name=f"IMG_{index:03d}_{view}.jpg",
            )
        )
    return CapturePackage(
        client_package_id=str(uuid.uuid4()),
        organization_id=args.organization_id,
        pen_id=args.pen_id,
        business_date=args.business_date,
        capture_kind="single" if len(assets) == 1 else "left_center_right",
        assets=assets,
    )


def run_profile(client: ContractClient, profile_name: str, args) -> dict:
    profile = PROFILES[profile_name]
    rng = random.Random(args.seed + hash(profile_name) % 1000)
    packages, outcomes, checks = [], [], []
    for index in range(args.packages):
        package = build_package(index, args)
        synchronizer = PackageSynchronizer(client, profile, rng=rng, logger=print)
        outcome = synchronizer.sync(package)
        packages.append(package)
        outcomes.append(outcome)
        checks.extend(verify(package, outcome, client))
    return {
        "profile": profile_name,
        "packages": len(packages),
        "outcomes": outcomes,
        "checks": checks,
        "synced": sum(1 for o in outcomes if o.synced),
        "pending": sum(1 for o in outcomes if not o.synced and not o.blocked_reason),
        "blocked": sum(1 for o in outcomes if o.blocked_reason),
        "blob_uploads": sum(o.blob_uploads for o in outcomes),
        "blob_skipped": sum(o.blob_skipped for o in outcomes),
        "blob_resends": sum(o.blob_resends for o in outcomes),
        "commit_attempts": sum(o.commit_attempts for o in outcomes),
        "faults": _merge_faults(outcomes),
    }


def _merge_faults(outcomes) -> dict:
    merged: dict[str, int] = {}
    for outcome in outcomes:
        for key, value in outcome.faults.items():
            merged[key] = merged.get(key, 0) + value
    return merged


def print_probe(findings: list[dict]) -> None:
    print("=== 契约探针（App 4 步上传合同）===")
    for item in findings:
        mark = "OK  " if item["implemented"] else "MISS"
        problem = "problem+json" if item["problem_json"] else item["content_type"] or "-"
        print(f"  [{mark}] {item['method']:4s} {item['path']:52s} -> "
              f"HTTP {item['status']} ({problem})  {item['purpose']}")
    implemented = sum(1 for item in findings if item["implemented"])
    print(f"  实现 {implemented}/{len(findings)} 个合同端点\n")


def print_run(result: dict) -> None:
    print(f"=== 场景 {result['profile']} ===")
    print(f"  采集包 {result['packages']} 个：已同步 {result['synced']}，被拒 {result['blocked']}，"
          f"窗口内未同步 {result['pending']}")
    print(f"  blob：新建 {result['blob_uploads']}，按 existingAssets 跳过 {result['blob_skipped']}，"
          f"重发 {result['blob_resends']}；commit 尝试 {result['commit_attempts']} 次")
    if result["faults"]:
        print("  注入故障：" + "，".join(f"{k}×{v}" for k, v in sorted(result["faults"].items())))
    failed = [c for c in result["checks"] if c["ok"] is False]
    skipped = [c for c in result["checks"] if c["ok"] is None]
    for check in result["checks"]:
        mark = "PASS" if check["ok"] else ("N/A " if check["ok"] is None else "FAIL")
        print(f"    [{mark}] {check['id']} {check['name']}"
              f"{(' — ' + check['detail']) if check['detail'] else ''}")
    if result["pending"]:
        print(f"  → {result['pending']} 个采集包在重试窗口内未同步（客户端仍在本地队列，"
              f"属于弱网下的正常状态，不计失败）")
    if failed:
        print(f"  → 本场景 {len(failed)}/{len(result['checks'])} 项不满足")
    elif skipped:
        print(f"  → 本场景通过（{len(skipped)} 项不适用）")
    print()


def detect_target_kind(client: ContractClient, base: str) -> str:
    """标注报告目标的性质：mock 上游 / 本仓库 Agent / 其它业务后端。

    报告会被当作证据引用，必须让人一眼看出它是不是对着真实后端跑的。
    """
    lowered = base.lower()
    if "127.0.0.1:8899" in lowered or "localhost:8899" in lowered:
        return "mock 上游（tools/fake_upstream.py，仅供自证脚本，不代表真实后端）"
    try:
        status, payload, headers = client._request("GET", "/health")  # noqa: SLF001
    except NetworkFault:
        return "目标不可达（未标注）"
    if isinstance(payload, dict) and payload.get("agent") == "pig-farm-agent":
        return (f"本仓库 Agent 后端（{payload.get('version')}，未实现 App 采集包合同）")
    # 未带令牌时 /health 会被写保护层拦下；此时用本仓库特有的错误信封识别
    if isinstance(payload, dict) and set(payload) == {"error_code", "message", "request_id"} \
            and "X-Request-Id" in {k.title() for k in headers}:
        return "本仓库 Agent 后端（未实现 App 采集包合同）"
    return "外部业务后端（smart-pig-inventory Spring 或等价实现）"


def render_report(base: str, findings: list[dict], runs: list[dict],
                  target_kind: str = "") -> str:
    lines = [
        "# App 弱网重放 / 契约探针报告",
        "",
        f"- 目标：`{base}`",
        f"- 目标性质：{target_kind or '未标注'}",
        f"- 生成时间：{datetime.now().astimezone().isoformat(timespec='seconds')}",
        "- 合同来源：smart-pig-inventory `contracts/openapi.yaml`（v0.8.0，`servers: /api/v1`）",
        "  与 `apps/mobile/lib/features/outbox/application/upload_package_synchronizer.dart`",
        "",
        "## 1. 契约探针",
        "",
        "| 步骤 | 方法 | 路径 | HTTP | 已实现 | 错误形状 |",
        "|---|---|---|---|---|---|",
    ]
    for item in findings:
        lines.append(
            f"| {item['step']} | {item['method']} | `{item['path']}` | {item['status']} | "
            f"{'✅' if item['implemented'] else '❌'} | "
            f"{'problem+json' if item['problem_json'] else (item['content_type'] or '-')} |"
        )
    lines += ["", "## 2. 弱网场景", ""]
    for result in runs:
        lines += [
            f"### {result['profile']}",
            "",
            f"- 采集包 {result['packages']} 个：已同步 {result['synced']}，被拒 {result['blocked']}，"
            f"窗口内未同步 {result['pending']}",
            f"- blob：新建 {result['blob_uploads']}，按 existingAssets 跳过 "
            f"{result['blob_skipped']}，重发 {result['blob_resends']}；"
            f"commit 尝试 {result['commit_attempts']} 次",
        ]
        if result["faults"]:
            lines.append("- 注入故障：" + "，".join(
                f"{k}×{v}" for k, v in sorted(result["faults"].items())))
        lines += ["", "| 不变量 | 结果 | 说明 |", "|---|---|---|"]
        for check in result["checks"]:
            mark = "✅" if check["ok"] else ("➖" if check["ok"] is None else "❌")
            lines.append(
                f"| {check['id']} {check['name']} | {mark} | {check['detail']} |"
            )
        lines.append("")
    applicable = sum(1 for r in runs for c in r["checks"] if c["ok"] is not None)
    failed = sum(1 for r in runs for c in r["checks"] if c["ok"] is False)
    not_applicable = sum(1 for r in runs for c in r["checks"] if c["ok"] is None)
    lines += [
        "## 3. 结论",
        "",
        f"- 不变量：{applicable - failed}/{applicable} 通过"
        f"（{not_applicable} 项因包在重试窗口内未同步而不适用）。",
        f"- 合同端点：{sum(1 for i in findings if i['implemented'])}/{len(findings)} 已实现。",
        "",
        "> 未同步不代表失败：弱网未恢复时客户端会保留本地队列（不删除原图），"
        "下一轮继续按同一 `X-Idempotency-Key` 重放。",
        "",
    ]
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="按 App 真实上传合同做弱网重放与契约探针")
    parser.add_argument("--base", required=True, help="目标服务根地址，如 https://host:8443")
    parser.add_argument("--username", help="登录账号（App 合同需要 Bearer 令牌）")
    parser.add_argument("--password", help="登录口令")
    parser.add_argument("--token", help="已有 access token（免登录）")
    parser.add_argument("--organization-id", default="00000000-0000-0000-0000-000000000001")
    parser.add_argument("--pen-id", default="00000000-0000-0000-0000-000000000002")
    parser.add_argument("--business-date", default=date.today().isoformat())
    parser.add_argument("--packages", type=int, default=1, help="每个场景的采集包数量")
    parser.add_argument("--assets-per-package", type=int, default=1, choices=(1, 3))
    parser.add_argument("--profile", default="clean",
                        help="clean|flaky|offline-recovery|partial-resume|token-expiry|harsh|all")
    parser.add_argument("--seed", type=int, default=20260916)
    parser.add_argument("--timeout", type=float, default=10.0)
    parser.add_argument("--probe-only", action="store_true", help="只做契约探针，不写数据")
    parser.add_argument("--skip-probe", action="store_true", help="跳过契约探针")
    parser.add_argument("--target-kind", help="目标性质标注（默认自动识别）")
    parser.add_argument("--report", help="报告输出路径（Markdown）")
    parser.add_argument("--json", dest="json_out", help="原始结果 JSON 输出路径")
    args = parser.parse_args(argv)

    client = ContractClient(args.base, access_token=args.token, username=args.username,
                            password=args.password, timeout=args.timeout)

    # 身份：App 合同全部写操作都要 Bearer
    if args.username and args.password and not args.token:
        try:
            status, payload = client.login()
        except NetworkFault as exc:
            print(f"目标不可达：{exc}", file=sys.stderr)
            return 2
        if status not in (200, 201):
            print(f"登录失败 HTTP {status}: {payload}", file=sys.stderr)
            return 2
        print(f"已登录（accessToken 长度 {len(client.access_token or '')}）\n")

    findings = []
    target_kind = args.target_kind or detect_target_kind(client, args.base)
    if not args.skip_probe:
        findings = probe_contract(client)
        print(f"目标性质：{target_kind}\n")
        print_probe(findings)

    if args.probe_only:
        implemented = sum(1 for i in findings if i["implemented"])
        if args.report:
            Path(args.report).parent.mkdir(parents=True, exist_ok=True)
            Path(args.report).write_text(
                render_report(args.base, findings, [], target_kind), encoding="utf-8")
            print(f"报告已写入 {args.report}")
        return 0 if implemented == len(findings) else 1

    if not client.access_token:
        print("缺少令牌：App 合同需要 --username/--password 或 --token", file=sys.stderr)
        return 2

    names = list(PROFILES) if args.profile == "all" else [args.profile]
    unknown = [n for n in names if n not in PROFILES]
    if unknown:
        print(f"未知场景：{unknown}（可选 {list(PROFILES)}）", file=sys.stderr)
        return 2

    runs = []
    for name in names:
        result = run_profile(client, name, args)
        runs.append(result)
        print_run(result)

    total = sum(1 for r in runs for c in r["checks"] if c["ok"] is not None)
    failed = sum(1 for r in runs for c in r["checks"] if c["ok"] is False)
    skipped = sum(1 for r in runs for c in r["checks"] if c["ok"] is None)
    synced = sum(r["synced"] for r in runs)
    print(f"总计：不变量 {total - failed}/{total} 通过（{skipped} 项不适用）；"
          f"同步成功 {synced} 个采集包")

    if args.report:
        Path(args.report).parent.mkdir(parents=True, exist_ok=True)
        Path(args.report).write_text(
            render_report(args.base, findings, runs, target_kind), encoding="utf-8")
        print(f"报告已写入 {args.report}")
    if args.json_out:
        payload = {
            "base": args.base,
            "target_kind": target_kind,
            "probe": findings,
            "runs": [
                {
                    "profile": r["profile"],
                    "synced": r["synced"],
                    "pending": r["pending"],
                    "blocked": r["blocked"],
                    "blob_uploads": r["blob_uploads"],
                    "blob_skipped": r["blob_skipped"],
                    "blob_resends": r["blob_resends"],
                    "commit_attempts": r["commit_attempts"],
                    "faults": r["faults"],
                    "checks": r["checks"],
                }
                for r in runs
            ],
        }
        Path(args.json_out).parent.mkdir(parents=True, exist_ok=True)
        Path(args.json_out).write_text(
            json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
        print(f"原始结果已写入 {args.json_out}")

    return 0 if failed == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
