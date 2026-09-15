import 'review_status.dart';

/// An Admin's moderation action against a review (`moderateReview` callable,
/// Ratings/Reviews v1 Stage 3/8). Byte-for-byte mirror of
/// `functions/src/lib/reviews/validation.ts`'s `MODERATION_ACTIONS` - the
/// wire value sent to the callable's `action` field.
enum ReviewModerationAction { hide, restore, reject }

extension ReviewModerationActionX on ReviewModerationAction {
  String get wireValue => name;

  /// The verb shown on the confirmation control (e.g. "Hide Review").
  String get label {
    switch (this) {
      case ReviewModerationAction.hide:
        return 'Hide Review';
      case ReviewModerationAction.restore:
        return 'Restore Review';
      case ReviewModerationAction.reject:
        return 'Reject Review';
    }
  }

  /// The [ReviewStatus] this action transitions a review TO - the exact same
  /// mapping `moderateReview.ts`'s own `targetStatusFor` uses server-side.
  ReviewStatus get targetStatus {
    switch (this) {
      case ReviewModerationAction.hide:
        return ReviewStatus.hidden;
      case ReviewModerationAction.restore:
        return ReviewStatus.published;
      case ReviewModerationAction.reject:
        return ReviewStatus.rejected;
    }
  }
}
