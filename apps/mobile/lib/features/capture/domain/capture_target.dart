class CaptureTarget {
  const CaptureTarget({
    required this.organizationId,
    required this.penId,
    required this.label,
    required this.businessDate,
    this.draftId,
  });

  final String organizationId;
  final String penId;
  final String? draftId;
  final String label;
  final DateTime businessDate;
}
