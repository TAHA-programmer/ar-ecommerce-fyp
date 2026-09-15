import '../../../reviews/models/review_status.dart';

/// The Admin Reviews screen's status filter (Ratings/Reviews v1 Stage 8).
/// [flagged] is orthogonal to [ReviewStatus] - a flagged review can be in
/// any status (most often still `published`, pending a decision) - so it's
/// its own filter value rather than a fourth [ReviewStatus].
enum AdminReviewFilter { all, flagged, published, hidden, rejected }

extension AdminReviewFilterX on AdminReviewFilter {
  String get label {
    switch (this) {
      case AdminReviewFilter.all:
        return 'All';
      case AdminReviewFilter.flagged:
        return 'Flagged';
      case AdminReviewFilter.published:
        return 'Published';
      case AdminReviewFilter.hidden:
        return 'Hidden';
      case AdminReviewFilter.rejected:
        return 'Rejected';
    }
  }
}
