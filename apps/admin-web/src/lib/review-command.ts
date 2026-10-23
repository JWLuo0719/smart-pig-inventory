export type ReviewMode = "confirm" | "correction";

export function candidateDifference(value: string, candidate: number | null | undefined): string {
  if (candidate == null) return "未知（服务端未提供候选）";
  if (!/^\d+$/.test(value.trim())) return "待输入有效人工数量";
  const count = Number(value);
  if (!Number.isSafeInteger(count) || count > 2147483647) return "待输入有效人工数量";
  const difference = count - candidate;
  return `${difference > 0 ? "+" : ""}${difference} 头`;
}

export function reviewCommand(mode: ReviewMode, value: string, reason: string, candidate: number | null) {
  if (!/^\d+$/.test(value.trim())) throw new Error("请输入不小于 0 的整数数量。");
  const count = Number(value);
  if (!Number.isSafeInteger(count) || count > 2147483647) throw new Error("数量超出允许范围。");
  const normalized = reason.trim().replace(/\s+/g, " ");
  if ((mode === "correction" || candidate === null || candidate !== count || normalized.length > 0) && (normalized.length < 8 || normalized.length > 500)) {
    throw new Error("请填写 8—500 个字符的确认或更正依据。");
  }
  const body = mode === "confirm" ? { confirmedCount: count, reason: normalized || null } : { correctedCount: count, reason: normalized };
  return { count, body, intent: JSON.stringify(body) };
}

export function containRect(width: number, height: number, boxWidth: number, boxHeight: number) {
  const scale = Math.min(boxWidth / width, boxHeight / height);
  return { left: (boxWidth - width * scale) / 2, top: (boxHeight - height * scale) / 2, width: width * scale, height: height * scale };
}
