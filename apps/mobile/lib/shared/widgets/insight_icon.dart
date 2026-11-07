import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Icons for rule-engine insights and model suggestions.
///
/// These used to be emoji glyphs rendered inside Text. Emoji baseline, metrics
/// and appearance vary per device font, so they never aligned with the
/// Material icons beside them. The semantic label keeps the meaning available
/// to screen readers, which a bare emoji did not provide.
class SeverityIcon extends StatelessWidget {
  const SeverityIcon(this.severity, {super.key});

  final String severity;

  @override
  Widget build(BuildContext context) {
    final (IconData icon, Color color, String label) = switch (severity) {
      'action' => (Icons.error_outline, AppColors.alert, '需要处理'),
      'warning' => (Icons.warning_amber_outlined, AppColors.straw, '提醒'),
      'success' => (Icons.check_circle_outline, AppColors.herdTeal, '正常'),
      _ => (Icons.lightbulb_outline, AppColors.barnBlueLight, '提示'),
    };
    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: Icon(icon, color: color, size: 18, semanticLabel: label),
    );
  }
}

/// Badge marking content produced by the rule engine or the detection model,
/// so it stays visually distinct from confirmed business facts.
class ModelBadge extends StatelessWidget {
  const ModelBadge({this.label = '模型', super.key});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.review.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.auto_awesome_outlined,
                size: 13, color: AppColors.review),
            const SizedBox(width: 4),
            Text(label,
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.review)),
          ],
        ),
      );
}
