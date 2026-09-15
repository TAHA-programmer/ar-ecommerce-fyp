// ignore_for_file: prefer_initializing_formals
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../core/models/product/product_summary_model.dart';
import '../../../product_details/repositories/product_details_repository.dart';
import '../../../reviews/models/review_model.dart';
import '../../../reviews/models/review_moderation_action.dart';
import '../../../reviews/models/review_report_model.dart';
import '../../../reviews/models/review_status.dart';
import '../../../reviews/repositories/admin_reviews_repository.dart';
import '../models/admin_review_filter.dart';

/// Drives the Admin "Reviews" screen (Ratings/Reviews v1 Stage 8) - every
/// review across every product, filterable by status/flagged, always
/// flagged-first within whatever filter is active, plus the per-review
/// hide/restore/reject moderation action and its audit-trail report list.
///
/// Mirrors `MyReviewsViewModel`'s established "resolve N product summaries,
/// isolate a per-item failure, never block the rest" pattern for showing
/// each review's product title, and `ReviewsViewModel`'s "reload the whole
/// list after a successful mutation rather than patch it in place" pattern
/// after a moderation action.
class AdminReviewsViewModel extends ChangeNotifier {
  final AdminReviewsRepository _repository;
  final ProductDetailsRepository _productDetailsRepository;

  AdminReviewsViewModel({
    required AdminReviewsRepository repository,
    required ProductDetailsRepository productDetailsRepository,
  }) : _repository = repository,
       _productDetailsRepository = productDetailsRepository {
    _load();
  }

  bool _isLoading = true;
  bool get isLoading => _isLoading;

  bool _loadFailed = false;

  /// An error surfaces only when it left us with nothing to show at all -
  /// same convention as `ReviewsViewModel`/`MyReviewsViewModel`.
  bool get hasLoadError => _loadFailed && _reviews.isEmpty;

  /// Empty because there's genuinely nothing matching the CURRENT [filter] -
  /// distinct from [hasLoadError] (nothing loaded at all).
  bool get isEmpty => !_isLoading && !hasLoadError && filteredReviews.isEmpty;

  List<ReviewModel> _reviews = const [];

  AdminReviewFilter _filter = AdminReviewFilter.all;
  AdminReviewFilter get filter => _filter;

  void setFilter(AdminReviewFilter filter) {
    if (filter == _filter) return;
    _filter = filter;
    notifyListeners();
  }

  int get flaggedCount => _reviews.where((r) => r.flaggedForReview).length;

  /// [_reviews] narrowed by [filter], then sorted flagged-for-review FIRST
  /// (v1 §0 decision 11's "flag for Admin attention" made visible as actual
  /// list priority), then newest first within each group.
  List<ReviewModel> get filteredReviews {
    Iterable<ReviewModel> result = _reviews;
    switch (_filter) {
      case AdminReviewFilter.all:
        break;
      case AdminReviewFilter.flagged:
        result = result.where((r) => r.flaggedForReview);
        break;
      case AdminReviewFilter.published:
        result = result.where((r) => r.status == ReviewStatus.published);
        break;
      case AdminReviewFilter.hidden:
        result = result.where((r) => r.status == ReviewStatus.hidden);
        break;
      case AdminReviewFilter.rejected:
        result = result.where((r) => r.status == ReviewStatus.rejected);
        break;
    }
    final list = result.toList()
      ..sort((a, b) {
        if (a.flaggedForReview != b.flaggedForReview) {
          return a.flaggedForReview ? -1 : 1;
        }
        return b.createdAt.compareTo(a.createdAt);
      });
    return list;
  }

  final Map<String, ProductSummaryModel> _productSummaries = {};

  /// The resolved product summary for [productId], or `null` if it hasn't
  /// resolved yet (or resolution failed / the product is gone) - a card
  /// renders a generic fallback (the raw id) in that case, never blanks out.
  ProductSummaryModel? productSummaryFor(String productId) =>
      _productSummaries[productId];

  Future<void> _load() async {
    _isLoading = true;
    _loadFailed = false;
    notifyListeners();

    try {
      _reviews = await _repository.fetchReviews();
    } catch (_) {
      _loadFailed = true;
    }

    _isLoading = false;
    notifyListeners();
    unawaited(_resolveProductSummaries(_reviews));
  }

  Future<void> _resolveProductSummaries(
    List<ReviewModel> reviewsToResolve,
  ) async {
    final missingProductIds = <String>{
      for (final review in reviewsToResolve)
        if (!_productSummaries.containsKey(review.productId)) review.productId,
    };
    if (missingProductIds.isEmpty) return;

    final resolved = await Future.wait(
      missingProductIds.map((productId) async {
        try {
          final detail = await _productDetailsRepository.getProductDetails(
            productId,
          );
          return MapEntry(productId, detail.summary);
        } catch (_) {
          return null; // resolution failure - the review still shows.
        }
      }),
    );

    for (final entry in resolved) {
      if (entry != null) _productSummaries[entry.key] = entry.value;
    }
    notifyListeners();
  }

  /// Re-runs the initial load from scratch - pull-to-refresh.
  Future<void> refresh() => _load();

  // --- Report audit trail (lazy, per review) ---

  final Map<String, List<ReviewReportModel>> _reportsByReviewId = {};
  final Set<String> _loadingReportsReviewIds = {};

  bool isLoadingReports(String reviewId) =>
      _loadingReportsReviewIds.contains(reviewId);

  /// The reports fetched so far for [reviewId], or `null` if
  /// [loadReportsFor] hasn't been called (or hasn't resolved) yet.
  List<ReviewReportModel>? reportsFor(String reviewId) =>
      _reportsByReviewId[reviewId];

  /// Fetches and caches the report audit trail for [reviewId] - a no-op if
  /// already loaded or already in flight, so expanding/collapsing the same
  /// card's "View reports" repeatedly never re-fetches.
  Future<void> loadReportsFor(String reviewId) async {
    if (_reportsByReviewId.containsKey(reviewId)) return;
    if (_loadingReportsReviewIds.contains(reviewId)) return;
    _loadingReportsReviewIds.add(reviewId);
    notifyListeners();
    try {
      _reportsByReviewId[reviewId] = await _repository.fetchReportsForReview(
        reviewId,
      );
    } catch (_) {
      _reportsByReviewId[reviewId] = const [];
    } finally {
      _loadingReportsReviewIds.remove(reviewId);
      notifyListeners();
    }
  }

  // --- Moderation ---

  final Set<String> _moderatingReviewIds = {};
  bool isModerating(String reviewId) => _moderatingReviewIds.contains(reviewId);

  static const String _busyMessage =
      'Please wait for the current request to finish.';

  /// Hides, restores, or rejects [reviewId] with a REQUIRED [reason] (v1 §0
  /// decision 12 - enforced again server-side regardless of client
  /// validation). Returns `null` on success (and reloads the whole list, so
  /// the new status/moderation stamp is immediately reflected) or a clean
  /// error message; refused with [_busyMessage] if a moderation action is
  /// already in flight for this SAME review.
  Future<String?> moderate({
    required String reviewId,
    required ReviewModerationAction action,
    required String reason,
  }) async {
    if (_moderatingReviewIds.contains(reviewId)) return _busyMessage;
    _moderatingReviewIds.add(reviewId);
    notifyListeners();
    try {
      final error = await _repository.moderateReview(
        reviewId: reviewId,
        action: action,
        reason: reason,
      );
      if (error == null) {
        await _load();
      }
      return error;
    } finally {
      _moderatingReviewIds.remove(reviewId);
      notifyListeners();
    }
  }
}
