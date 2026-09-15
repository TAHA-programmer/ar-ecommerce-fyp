/// Why a customer reported someone else's review (`reviewReports/{id}.reason`).
enum ReviewReportReason { spam, offensive, fake, other }

extension ReviewReportReasonX on ReviewReportReason {
  String get wireValue => name;

  String get label {
    switch (this) {
      case ReviewReportReason.spam:
        return 'Spam';
      case ReviewReportReason.offensive:
        return 'Offensive';
      case ReviewReportReason.fake:
        return 'Fake / not a genuine review';
      case ReviewReportReason.other:
        return 'Other';
    }
  }

  static ReviewReportReason fromWire(String value) {
    return ReviewReportReason.values.firstWhere(
      (r) => r.wireValue == value,
      orElse: () => ReviewReportReason.other,
    );
  }
}
