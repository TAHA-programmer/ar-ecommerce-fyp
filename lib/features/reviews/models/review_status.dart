/// A review's moderation state (`reviews/{id}.status`).
///
/// Only [published] reviews are ever shown to another customer or counted in
/// `productStats`'s rating aggregate (Ratings/Reviews v1 §0/§3,
/// `24_RATINGS_REVIEWS_FEEDBACK_PLAN.md`). [hidden]/[rejected] are both
/// Admin-moderation outcomes distinguished only by intent (temporarily
/// hidden pending appeal vs. permanently rejected) - both are equally
/// excluded from public view and the aggregate.
enum ReviewStatus { published, hidden, rejected }

extension ReviewStatusX on ReviewStatus {
  String get wireValue => name;

  /// Unrecognised/corrupt data fails CLOSED to [hidden] - never silently
  /// treated as [published] and shown to other customers.
  static ReviewStatus fromWire(String value) {
    return ReviewStatus.values.firstWhere(
      (s) => s.wireValue == value,
      orElse: () => ReviewStatus.hidden,
    );
  }

  /// Whether a review in this state counts toward `productStats`'s rating
  /// aggregate (v1 decision: "Only published reviews contribute").
  bool get countsTowardAggregate => this == ReviewStatus.published;
}
