/// Single source of truth for review field limits (Ratings/Reviews v1 §0).
/// The `submitReview` Cloud Function (Stage 2) mirrors these exact numbers
/// server-side - the server check is the real gate, this is what the client
/// form/validation reads so the two can never silently drift apart.
class ReviewValidation {
  ReviewValidation._();

  static const int minRating = 1;
  static const int maxRating = 5;

  static const int maxTitleLength = 80;

  static const int minBodyLength = 10;
  static const int maxBodyLength = 1000;

  /// A review may be edited for this many days after its ORIGINAL
  /// [ReviewModel.createdAt] - never reset by an edit's own [ReviewModel.editedAt].
  static const int editWindowDays = 30;

  /// Unique-reporter count at which a review is flagged for Admin attention
  /// (`reviews/{id}.flaggedForReview`). Never auto-hidden - manual moderation
  /// stays authoritative (v1 §0 decision 11).
  static const int reportFlagThreshold = 3;

  /// Optional free-text note a reporter may add to a report
  /// (`reviewReports/{id}.note`) - mirrors
  /// `functions/src/config.ts`'s `REVIEW_REPORT_NOTE_MAX_LENGTH` (Stage 8).
  static const int reportNoteMaxLength = 500;

  /// The reason an Admin gives for a hide/restore/reject moderation action -
  /// required for EVERY action (v1 §0 decision 12), captured verbatim in
  /// `reviews/{id}.moderationReason`. Mirrors `functions/src/config.ts`'s
  /// `REVIEW_MODERATION_REASON_MAX_LENGTH` (Stage 8).
  static const int moderationReasonMaxLength = 500;

  static bool isRatingValid(int rating) =>
      rating >= minRating && rating <= maxRating;

  static bool isTitleValid(String? title) =>
      title == null || title.length <= maxTitleLength;

  static bool isBodyValid(String body) =>
      body.length >= minBodyLength && body.length <= maxBodyLength;

  static bool isReportNoteValid(String? note) =>
      note == null || note.length <= reportNoteMaxLength;

  /// A moderation reason must be non-empty (after trimming) - the server
  /// rejects a blank reason for every action, including `restore`.
  static bool isModerationReasonValid(String reason) {
    final trimmed = reason.trim();
    return trimmed.isNotEmpty && trimmed.length <= moderationReasonMaxLength;
  }
}
