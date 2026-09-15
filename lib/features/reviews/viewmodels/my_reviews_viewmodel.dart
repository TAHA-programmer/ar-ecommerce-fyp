// ignore_for_file: prefer_initializing_formals
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/models/product/product_summary_model.dart';
import '../../product_details/repositories/product_details_repository.dart';
import '../models/review_model.dart';
import '../repositories/reviews_repository.dart';

/// Drives the Profile "My Reviews" screen (Ratings/Reviews v1 Stage 7) - the
/// signed-in customer's own reviews across every product, each resolved
/// against its product's title/thumbnail for display. Mirrors
/// `FavoritesViewModel`'s established "resolve N product summaries,
/// isolate a per-item failure, never block the rest" pattern - a deleted or
/// unresolvable product must never hide the review itself, since the
/// customer's own written content is the primary thing this screen exists
/// to show.
class MyReviewsViewModel extends ChangeNotifier {
  final ReviewsRepository _repository;
  final ProductDetailsRepository _productDetailsRepository;

  MyReviewsViewModel({
    required ReviewsRepository repository,
    required ProductDetailsRepository productDetailsRepository,
  }) : _repository = repository,
       _productDetailsRepository = productDetailsRepository {
    _load();
  }

  bool _isLoading = true;
  bool get isLoading => _isLoading;

  bool _loadFailed = false;

  /// An error surfaces only when it left us with nothing to show - same
  /// convention as `RecentlyViewedViewModel`/`ReviewsViewModel`.
  bool get hasLoadError => _loadFailed && _reviews.isEmpty;

  bool get isEmpty => !_isLoading && !hasLoadError && _reviews.isEmpty;

  List<ReviewModel> _reviews = const [];
  List<ReviewModel> get reviews => _reviews;

  final Map<String, ProductSummaryModel> _productSummaries = {};

  /// The resolved product summary for [productId], or `null` if it hasn't
  /// resolved yet (or the resolution failed / the product is gone) - a
  /// card renders a generic fallback in that case, never blanks itself out.
  ProductSummaryModel? productSummaryFor(String productId) =>
      _productSummaries[productId];

  final Set<String> _deletingReviewIds = {};
  bool isDeleting(String reviewId) => _deletingReviewIds.contains(reviewId);

  static const String _busyMessage =
      'Please wait for the current request to finish.';

  Future<void> _load() async {
    _isLoading = true;
    _loadFailed = false;
    notifyListeners();

    try {
      _reviews = await _repository.myReviews();
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

  /// Re-runs the initial load from scratch - pull-to-refresh, and also
  /// called after returning from the Write/Edit screen having made a
  /// change.
  Future<void> refresh() => _load();

  /// Deletes [review]. Returns `null` on success (and removes it from the
  /// in-memory list immediately, no full reload needed) or a clean error
  /// message. Refused with [_busyMessage] if a delete for this SAME review
  /// is already in flight.
  Future<String?> deleteReview(ReviewModel review) async {
    if (_deletingReviewIds.contains(review.id)) return _busyMessage;
    _deletingReviewIds.add(review.id);
    notifyListeners();
    try {
      final error = await _repository.deleteReview(review.productId);
      if (error == null) {
        _reviews = _reviews.where((r) => r.id != review.id).toList();
      }
      return error;
    } finally {
      _deletingReviewIds.remove(review.id);
      notifyListeners();
    }
  }
}
