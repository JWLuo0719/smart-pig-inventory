package com.smartfarm.inventory.inventory.application;

import com.smartfarm.inventory.inventory.infrastructure.JdbcAssistantInsightRepository;
import com.smartfarm.inventory.inventory.infrastructure.JdbcAssistantInsightRepository.AssistantRow;
import com.smartfarm.inventory.inventory.infrastructure.JdbcAssistantInsightRepository.PenHistoryRow;
import com.smartfarm.inventory.inventory.infrastructure.SecurityReviewActor;
import java.time.LocalDate;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 证据驱动的智能体研判：把当日每栏的真实状态翻译成场长能直接执行的提醒。
 *
 * 全部结论由规则从数据库事实生成（会话状态、候选/确认数量、历史对比、
 * 推理失败码），不调用外部大模型，保证离线可用、口径可审计——与
 * “机器提议、人签字”的治理边界一致：洞察只组织证据与建议，不产生业务值。
 */
@Service
public class AssistantInsightService {

    private final JdbcAssistantInsightRepository repository;
    private final SecurityReviewActor actor;

    public AssistantInsightService(JdbcAssistantInsightRepository repository, SecurityReviewActor actor) {
        this.repository = repository;
        this.actor = actor;
    }

    @Transactional(readOnly = true)
    public AssistantBrief insights(LocalDate businessDate) {
        UUID organizationId = actor.activeOrganizationId();
        actor.assertCanView(organizationId);
        return build(businessDate, repository.listOrganizationDay(organizationId, businessDate),
                repository.listConfirmedHistory(organizationId, businessDate, 7));
    }

    static AssistantBrief build(LocalDate businessDate, List<AssistantRow> rows) {
        return build(businessDate, rows, List.of());
    }

    static AssistantBrief build(LocalDate businessDate, List<AssistantRow> rows, List<PenHistoryRow> history) {
        List<Insight> insights = new ArrayList<>();
        if (rows.isEmpty()) {
            return new AssistantBrief(businessDate,
                    "尚未建立栏舍台账，请先在管理后台维护栋舍与栏舍。",
                    List.of(new Insight("EMPTY_MASTER_DATA", "info",
                            "还没有可盘点的栏舍", "栏舍台账为空；任务由管理后台按栏舍创建。", null, null, "去管理后台")));
        }

        List<AssistantRow> reviewRows = rows.stream()
                .filter(row -> "review_required".equals(row.status()))
                .toList();
        List<AssistantRow> pendingRows = rows.stream()
                .filter(row -> row.sessionId() == null || "pending".equals(row.status()))
                .toList();
        long confirmedCount = rows.stream().filter(row -> "confirmed".equals(row.status())).count();
        int totalHeads = rows.stream()
                .filter(row -> "confirmed".equals(row.status()) && row.confirmedCount() != null)
                .mapToInt(AssistantRow::confirmedCount)
                .sum();

        for (AssistantRow row : reviewRows) {
            insights.add(reviewInsight(row));
        }
        reviewRows.stream()
                .max(Comparator.comparingInt(AssistantInsightService::reviewWeight))
                .ifPresent(top -> insights.add(new Insight("REVIEW_HINT", "info",
                        "建议先复核 " + penLabel(top),
                        biggestChangeDetail(top) + "；复核确认后证据自动锁定。",
                        top.sessionId(), penLabel(top), "去复核")));

        if (!pendingRows.isEmpty()) {
            List<String> labels = pendingRows.stream().map(AssistantInsightService::penLabel).toList();
            String names = String.join("、",
                    labels.subList(0, Math.min(labels.size(), 5))
                            .stream().map(label -> label.replaceAll("（.*）", "")).toList());
            String extra = labels.size() > 5 ? "等" : "";
            insights.add(new Insight("PENDING_CAPTURE", pendingRows.size() == 1 ? "action" : "info",
                    pendingRows.size() == 1 ? names + " 今日尚未采集"
                            : "%d 个栏舍今日尚未采集（%s%s）".formatted(labels.size(), names, extra),
                    "在收工前补齐采集，日报才会覆盖全部栏舍。",
                    null, null, "去采集"));
        }

        insights.addAll(riskInsights(businessDate, rows, history));

        boolean allConfirmed = confirmedCount == rows.size();
        if (confirmedCount > 0) {
            insights.add(new Insight("DAY_SUMMARY", allConfirmed ? "success" : "info",
                    allConfirmed ? "今日盘点全部完成"
                            : "已确认 %d/%d 栏".formatted(confirmedCount, rows.size()),
                    allConfirmed
                            ? "%d 栏存栏合计 %d 头，证据已锁定，日报可导出。".formatted(confirmedCount, totalHeads)
                            : "已确认栏存栏合计 %d 头；完成剩余复核后生成完整日报。".formatted(totalHeads),
                    null, null, "查看日报"));
        }

        String brief = "%s：待复核 %d 栏、未采集 %d 栏；已确认 %d/%d 栏%s。"
                .formatted(businessDate, reviewRows.size(), pendingRows.size(),
                        confirmedCount, rows.size(),
                        confirmedCount > 0 ? "，存栏合计 " + totalHeads + " 头" : "");
        return new AssistantBrief(businessDate, brief, List.copyOf(insights));
    }

    /**
     * 健康风险候选（规则版）：只使用可解释的统计事实——确认数量的近 7 日
     * 中位数与采集断档天数。数量下降触发风险候选（严重时要求行动），
     * 上升仅提示核实；输出始终是“候选 + 证据”，不构成诊断。
     */
    private static List<Insight> riskInsights(LocalDate businessDate, List<AssistantRow> rows,
            List<PenHistoryRow> history) {
        List<Insight> insights = new ArrayList<>();
        Map<UUID, List<PenHistoryRow>> byPen = new LinkedHashMap<>();
        for (PenHistoryRow row : history) {
            byPen.computeIfAbsent(row.penId(), ignored -> new ArrayList<>()).add(row);
        }
        for (AssistantRow row : rows) {
            List<PenHistoryRow> penHistory = byPen.getOrDefault(row.penId(), List.of());
            if (row.sessionId() == null && row.lastConfirmedDate() != null) {
                long gapDays = ChronoUnit.DAYS.between(row.lastConfirmedDate(), businessDate);
                if (gapDays >= 3) {
                    insights.add(new Insight("CAPTURE_GAP", "action", penLabel(row) + " 已 " + gapDays + " 天未采集",
                            "上次确认是 %s（%d 头）；连续缺采会让趋势与基线失效，建议今天补采。"
                                    .formatted(row.lastConfirmedDate(), row.lastConfirmedCount()),
                            null, penLabel(row), "去采集"));
                }
            }
            Integer today = row.confirmedCount() != null ? row.confirmedCount()
                    : ("review_required".equals(row.status()) ? row.candidateCount() : null);
            int baseline = median(penHistory.stream().map(PenHistoryRow::confirmedCount).toList());
            if (today == null || baseline < 5 || penHistory.size() < 2) {
                continue;
            }
            int delta = today - baseline;
            int pct = Math.abs(delta) * 100 / baseline;
            if (pct < 20) {
                continue;
            }
            boolean drop = delta < 0;
            insights.add(new Insight(drop ? "RISK_CANDIDATE" : "BASELINE_SHIFT", drop ? "action" : "info",
                    "%s 数量较基线%s %d%%".formatted(penLabel(row), drop ? "下降" : "上升", pct),
                    "今日 %d 头，近 7 日中位 %d 头（%d 次确认）。%s".formatted(today, baseline, penHistory.size(),
                            drop ? "数量下降属健康风险候选信号，请现场核实转栏、出栏或异常；系统仅提示候选，不构成诊断。"
                                    : "数量上升请核实是否进猪或重复计数。"),
                    row.sessionId(), penLabel(row), drop ? "去复核" : "查看"));
        }
        return insights;
    }

    private static int median(List<Integer> values) {
        if (values.isEmpty()) {
            return 0;
        }
        List<Integer> sorted = values.stream().sorted().toList();
        int middle = sorted.size() / 2;
        return sorted.size() % 2 == 1 ? sorted.get(middle)
                : (sorted.get(middle - 1) + sorted.get(middle)) / 2;
    }

    private static Insight reviewInsight(AssistantRow row) {
        Integer candidate = row.candidateCount() != null ? row.candidateCount() : row.detectionCount();
        String label = penLabel(row);
        if (candidate == null || candidate == 0) {
            String cause = "failed".equals(row.inferenceStatus()) && row.failureCode() != null
                    ? "自动清点失败（%s）".formatted(row.failureCode())
                    : "未产生候选数量";
            return new Insight("REVIEW_REQUIRED", "action", label + " 待人工清点",
                    cause + "；请依据照片证据人工清点并确认。",
                    row.sessionId(), label, "去清点");
        }
        if (row.lastConfirmedCount() != null) {
            int delta = candidate - row.lastConfirmedCount();
            String trend = delta == 0 ? "与上次持平"
                    : "%+d 头（%s 上次 %d 头）".formatted(delta,
                            row.lastConfirmedDate() == null ? "历史" : row.lastConfirmedDate().toString(),
                            row.lastConfirmedCount());
            boolean notable = row.lastConfirmedCount() > 0
                    && Math.abs(delta) * 100.0 / row.lastConfirmedCount() >= 10.0;
            return new Insight("REVIEW_REQUIRED", notable ? "action" : "info",
                    label + " 待复核：候选 " + candidate + " 头",
                    trend + "；建议优先复核" + (notable ? "，数量变化较大" : "") + "。",
                    row.sessionId(), label, "去复核");
        }
        return new Insight("REVIEW_REQUIRED", "action", label + " 待复核：候选 " + candidate + " 头",
                "首次盘点，复核确认后计入存栏底数。",
                row.sessionId(), label, "去复核");
    }

    private static String biggestChangeDetail(AssistantRow row) {
        Integer candidate = row.candidateCount() != null ? row.candidateCount() : row.detectionCount();
        if (candidate != null && candidate > 0 && row.lastConfirmedCount() != null) {
            int delta = candidate - row.lastConfirmedCount();
            if (delta != 0) {
                return "候选 %d 头，比上次%s%+d".formatted(candidate,
                        row.lastConfirmedDate() == null ? "" : "（" + row.lastConfirmedDate() + "）",
                        delta);
            }
        }
        return "该栏候选数量变化最值得关注";
    }

    private static int reviewWeight(AssistantRow row) {
        Integer candidate = row.candidateCount() != null ? row.candidateCount() : row.detectionCount();
        if (candidate == null || row.lastConfirmedCount() == null || row.lastConfirmedCount() == 0) {
            return 0;
        }
        return Math.abs(candidate - row.lastConfirmedCount()) * 100 / row.lastConfirmedCount();
    }

    private static String penLabel(AssistantRow row) {
        return "%s%s（%s %s）".formatted(row.buildingCode(), row.penCode(), row.buildingName(), row.penName());
    }

    /**
     * 智能体研判结果。
     *
     * @param businessDate 业务日期
     * @param brief 一句话当日概览
     * @param insights 建议列表（有序：行动类在前）
     */
    public record AssistantBrief(LocalDate businessDate, String brief, List<Insight> insights) {
    }

    /**
     * 单条洞察。
     *
     * @param type 类型：REVIEW_REQUIRED / REVIEW_HINT / PENDING_CAPTURE / CAPTURE_GAP /
     *             RISK_CANDIDATE / BASELINE_SHIFT / DAY_SUMMARY / EMPTY_MASTER_DATA
     * @param severity 级别：action（需行动）/ info（提示）/ success（完成）
     * @param title 标题
     * @param detail 依据与建议（含数据出处）
     * @param sessionId 关联会话（可跳转复核）
     * @param penLabel 栏舍标签
     * @param action 行动按钮文案
     */
    public record Insight(String type, String severity, String title, String detail,
                          UUID sessionId, String penLabel, String action) {
    }
}
