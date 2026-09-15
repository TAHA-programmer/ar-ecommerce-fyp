import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../models/review_model.dart';
import '../models/review_moderation_action.dart';
import '../models/review_report_model.dart';
import 'admin_reviews_repository.dart';
import 'review_callable_errors.dart';
import 'review_firestore_mapper.dart';

/// Real [AdminReviewsRepository]: direct Firestore reads (rules-allowed to
/// an admin - `reviews`' `isAdmin()` clause, `reviewReports`' admin-only read
/// rule) + the `moderateReview` callable (Cloud Functions, `us-central1`,
/// already `TECH PASSED` since Stage 3) for the one mutation. Mirrors
/// [FirestoreReviewsRepository]'s established "direct Firestore reads,
/// callable-only writes" shape.
///
/// `moderateReview` is NOT deployed yet (Stage 3, local-only) - every call
/// this repository makes will fail until Stage 10's explicit, developer-
/// approved deploy. That is expected and does not change this repository's
/// contract: it still returns a clean, `AppToast`-ready message rather than
/// throwing.
class FirestoreAdminReviewsRepository implements AdminReviewsRepository {
  static const String _functionsRegion = 'us-central1';

  /// A bounded, single-query read across the WHOLE `reviews` collection
  /// (`orderBy('createdAt', descending: true)` - a single field, so no
  /// composite index is ever needed), matching this app's established
  /// "no new composite index for a bounded, in-memory-filtered read"
  /// convention (`FirestoreReviewsRepository.myReviews`/
  /// `isEligibleToReview`, `24_RATINGS_REVIEWS_FEEDBACK_PLAN.md` §14.2).
  /// Status/flagged filtering and flagged-first sorting both happen in Dart
  /// (`AdminReviewsViewModel`), never as an additional Firestore filter -
  /// generous at v1's expected review volume; revisit only if real volume
  /// ever approaches it (the exact caveat already accepted for the
  /// rating-sort window).
  static const int _reviewsLimit = 500;

  final FirebaseFirestore _firestore;
  final FirebaseFunctions? _injectedFunctions;

  FirestoreAdminReviewsRepository({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _injectedFunctions = functions;

  FirebaseFunctions get _functions =>
      _injectedFunctions ??
      FirebaseFunctions.instanceFor(region: _functionsRegion);

  CollectionReference<Map<String, dynamic>> get _reviewsCollection =>
      _firestore.collection('reviews');

  CollectionReference<Map<String, dynamic>> get _reviewReportsCollection =>
      _firestore.collection('reviewReports');

  @override
  Future<List<ReviewModel>> fetchReviews() async {
    try {
      final snapshot = await _reviewsCollection
          .orderBy('createdAt', descending: true)
          .limit(_reviewsLimit)
          .get();
      return snapshot.docs
          .map((d) => reviewModelFromFirestore(d.id, d.data()))
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<List<ReviewReportModel>> fetchReportsForReview(String reviewId) async {
    try {
      // Single-field `where` (auto-indexed, no composite index) - the exact
      // same strategy as every other bounded admin/customer read in this
      // feature (`myReviews`, `isEligibleToReview`); sorted newest-first in
      // Dart rather than a Firestore `orderBy` combined with the filter.
      final snapshot = await _reviewReportsCollection
          .where('reviewId', isEqualTo: reviewId)
          .get();
      final reports = snapshot.docs
          .map((d) => reviewReportModelFromFirestore(d.id, d.data()))
          .toList();
      reports.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return reports;
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<String?> moderateReview({
    required String reviewId,
    required ReviewModerationAction action,
    required String reason,
  }) async {
    try {
      final callable = _functions.httpsCallable(
        'moderateReview',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
      );
      await callable.call<Map<String, dynamic>>(<String, dynamic>{
        'reviewId': reviewId,
        'action': action.wireValue,
        'reason': reason,
      });
      return null;
    } on FirebaseFunctionsException catch (e) {
      return mapReviewCallableError(
        appCode: _appCodeOf(e),
        grpcCode: e.code,
        message: e.message,
      );
    } catch (_) {
      return 'Network error. Please check your connection and try again.';
    }
  }

  String? _appCodeOf(FirebaseFunctionsException e) {
    final details = e.details;
    if (details is Map) return details['appCode']?.toString();
    return null;
  }
}
