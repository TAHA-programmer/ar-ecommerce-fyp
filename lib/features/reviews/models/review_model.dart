import 'review_status.dart';
import 'review_validation.dart';

/// A single product review (`reviews/{userId}_{productId}` - Ratings/Reviews
/// v1, `24_RATINGS_REVIEWS_FEEDBACK_PLAN.md`).
///
/// The deterministic doc id (see [docIdFor]) is what enforces "one review
/// per user per product, even after repeat purchases" (v1 §0 decision 2) and
/// turns "submit again" into an edit-in-place rather than a second
/// document - there is no separate "edit" write shape, just a re-`set()` of
/// the same id.
///
/// This model is READ-ONLY from the client's perspective: every field here
/// is written exclusively by the `submitReview`/`deleteReview`/
/// `moderateReview` Cloud Functions (Stage 2/3) - `firestore.rules` denies
/// every direct client write to `reviews` (v1 §0 decision 14). A client
/// never constructs one of these to send to Firestore; it only ever reads
/// one back, or sends the raw rating/title/body to a callable and lets the
/// server build the document.
class ReviewModel {
  /// `{userId}_{productId}` - see [docIdFor].
  final String id;

  final String productId;
  final String userId;

  /// A SAFE, already-masked display name for the review's author (e.g.
  /// "Ayesha K."), computed server-side by `submitReview` from the
  /// author's OWN `users/{uid}.displayName` at submission time and stored
  /// directly on this document (Ratings/Reviews v1 §0 decision 13 / §6).
  ///
  /// This is a deliberate denormalized snapshot, NOT a live lookup: a
  /// client reading another customer's review can never read that other
  /// customer's `users/{uid}` profile document at all
  /// (`firestore.rules`' `users/{uid}` read rule is owner/admin-only) - so
  /// the ONLY safe way to show an author name on someone else's review is
  /// for the trusted server (Admin SDK, bypasses that rule) to resolve and
  /// mask it once, at write time, and publish just this already-safe
  /// string as a normal field on the (publicly `published`-readable)
  /// review document itself. Never email, phone, or any other raw account
  /// field - see `functions/src/lib/reviews/authorDisplayName.ts`'s
  /// Dart-mirrored masking logic.
  final String authorDisplayName;

  /// The qualifying delivered order at submission time - audit-only, never
  /// re-checked on read.
  final String orderId;

  /// 1-5 - see [ReviewValidation.isRatingValid].
  final int rating;

  /// ≤[ReviewValidation.maxTitleLength] chars, optional.
  final String? title;

  /// [ReviewValidation.minBodyLength]-[ReviewValidation.maxBodyLength] chars.
  final String body;

  final ReviewStatus status;

  /// Unique-reporter count, maintained by `reportReview` (Stage 3).
  final int reportCount;

  /// `true` once [reportCount] reaches [ReviewValidation.reportFlagThreshold] -
  /// an Admin-queue priority signal only, never an auto-hide (v1 §0
  /// decision 11).
  final bool flaggedForReview;

  final DateTime createdAt;

  /// `null` until the review has actually been edited at least once - never
  /// set on the original creation, so "has this review been edited" is a
  /// plain null-check, not a timestamp-equality comparison.
  final DateTime? editedAt;

  final DateTime? moderatedAt;
  final String? moderatedBy;

  /// Required by the server whenever [status] is [ReviewStatus.hidden] or
  /// [ReviewStatus.rejected] (v1 §0 decision 12) - `null` for a
  /// never-moderated, still-[ReviewStatus.published] review.
  final String? moderationReason;

  const ReviewModel({
    required this.id,
    required this.productId,
    required this.userId,
    required this.authorDisplayName,
    required this.orderId,
    required this.rating,
    this.title,
    required this.body,
    this.status = ReviewStatus.published,
    this.reportCount = 0,
    this.flaggedForReview = false,
    required this.createdAt,
    this.editedAt,
    this.moderatedAt,
    this.moderatedBy,
    this.moderationReason,
  });

  static String docIdFor({required String userId, required String productId}) =>
      '${userId}_$productId';

  /// `true` once this review has been edited at least once.
  bool get hasBeenEdited => editedAt != null;

  /// `true` while the ORIGINAL submission is still within the
  /// [ReviewValidation.editWindowDays]-day edit window (v1 §0 decision 6) -
  /// always measured from [createdAt], never reset by a prior edit, so a
  /// review cannot be kept perpetually editable by re-editing it just
  /// before the window closes.
  bool isEditableAt(DateTime now) {
    final deadline = createdAt.add(
      const Duration(days: ReviewValidation.editWindowDays),
    );
    return !now.isAfter(deadline);
  }

  ReviewModel copyWith({
    ReviewStatus? status,
    int? reportCount,
    bool? flaggedForReview,
    DateTime? editedAt,
    DateTime? moderatedAt,
    String? moderatedBy,
    String? moderationReason,
  }) {
    return ReviewModel(
      id: id,
      productId: productId,
      userId: userId,
      authorDisplayName: authorDisplayName,
      orderId: orderId,
      rating: rating,
      title: title,
      body: body,
      status: status ?? this.status,
      reportCount: reportCount ?? this.reportCount,
      flaggedForReview: flaggedForReview ?? this.flaggedForReview,
      createdAt: createdAt,
      editedAt: editedAt ?? this.editedAt,
      moderatedAt: moderatedAt ?? this.moderatedAt,
      moderatedBy: moderatedBy ?? this.moderatedBy,
      moderationReason: moderationReason ?? this.moderationReason,
    );
  }
}
