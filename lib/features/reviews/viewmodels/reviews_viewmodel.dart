// ignore_for_file: prefer_initializing_formals
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../app/viewmodels/auth_session_state.dart';
import '../models/product_rating_stats.dart';
import '../models/review_model.dart';
import '../models/review_report_reason.dart';
import '../models/review_sort_option.dart';
import '../models/reviews_page.dart';
import '../repositories/reviews_repository.dart';

/// Drives one product's reviews section (Ratings/Reviews v1, Stage 5) - the
/// paginated published-review list + rating aggregate + the signed-in
/// customer's own review/eligibility state, and every write action
/// (submit/edit/delete/report). Deliberately unwired from any screen this
/// stage - a future Product Details/Write-Review/Profile screen (Stage 6/7)
/// constructs one of these per `productId`, exactly like
/// `ProductDetailsViewModel`/`VirtualTryOnSetupViewModel` are constructed
/// per product today.
///
/// Every [ReviewsRepository] read method is documented as "never throws"
/// (fails closed to an empty/zero/null/false result) - the `try/catch`
/// around each read here is still kept, matching `RecentlyViewedViewModel`'s
/// established defensive-catch convention, so a future repository swap that
/// *does* throw can never crash this ViewModel or leave it stuck loading.
class ReviewsViewModel extends ChangeNotifier {
  final ReviewsRepository _repository;
  final AuthSessionState _authSessionState;
  final String productId;

  static const int _pageSize = 10;

  ReviewsViewModel({
    required ReviewsRepository repository,
    required AuthSessionState authSessionState,
    required this.productId,
  }) : _repository = repository,
       _authSessionState = authSessionState {
    _authSessionState.addListener(_onAuthChanged);
    _load();
  }

  @override
  void dispose() {
    _authSessionState.removeListener(_onAuthChanged);
    super.dispose();
  }

  // --- List / aggregate state ---

  bool _isLoading = true;
  bool get isLoading => _isLoading;

  bool _loadFailed = false;

  /// An error surfaces only when it left us with nothing to show - a
  /// transient failure with a resolved list still on screen stays silent
  /// (same convention as `RecentlyViewedViewModel.hasError`).
  bool get hasLoadError => _loadFailed && _reviews.isEmpty;

  bool get isEmpty => !_isLoading && !hasLoadError && _reviews.isEmpty;

  List<ReviewModel> _reviews = const [];
  List<ReviewModel> get reviews => _reviews;

  ProductRatingStats _stats = ProductRatingStats.zero;
  ProductRatingStats get stats => _stats;

  ReviewSortOption _sort = ReviewSortOption.newest;
  ReviewSortOption get sort => _sort;

  String? _cursor;
  bool _hasMore = false;
  bool get hasMore => _hasMore;

  bool _isLoadingMore = false;
  bool get isLoadingMore => _isLoadingMore;

  /// Bumped on every fresh load (initial, refresh, sort change, and after a
  /// successful mutation) - a stale in-flight request whose generation no
  /// longer matches the current one discards its result instead of
  /// clobbering a newer one (e.g. a slow initial load completing after the
  /// customer already switched sort order).
  int _loadGeneration = 0;

  // --- Own-state (signed-in customer) ---

  ReviewModel? _myReview;
  ReviewModel? get myReview => _myReview;

  bool _isEligibleToReview = false;
  bool get isEligibleToReview => _isEligibleToReview;

  bool isMine(ReviewModel review) =>
      _authSessionState.isAuthenticated &&
      review.userId == _authSessionState.userId;

  // --- Mutation in-flight guards (duplicate-request protection) ---

  bool _isSubmitting = false;
  bool get isSubmitting => _isSubmitting;

  bool _isDeleting = false;
  bool get isDeleting => _isDeleting;

  final Set<String> _reportingReviewIds = {};
  bool isReporting(String reviewId) => _reportingReviewIds.contains(reviewId);

  static const String _busyMessage =
      'Please wait for the current request to finish.';

  void _onAuthChanged() {
    unawaited(_loadOwnStateStandalone());
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    _isLoading = true;
    _loadFailed = false;
    notifyListeners();

    var page = ReviewsPage.empty;
    var stats = ProductRatingStats.zero;
    try {
      page = await _repository.fetchReviews(
        productId: productId,
        sort: _sort,
        pageSize: _pageSize,
      );
    } catch (_) {
      _loadFailed = true;
    }
    try {
      stats = await _repository.ratingStatsFor(productId);
    } catch (_) {
      _loadFailed = true;
    }
    final ownState = await _fetchOwnState();

    if (generation != _loadGeneration) return; // superseded, discard

    _reviews = page.reviews;
    _cursor = page.nextCursor;
    _hasMore = page.hasMore;
    _stats = stats;
    _myReview = ownState.myReview;
    _isEligibleToReview = ownState.isEligible;
    _isLoading = false;
    notifyListeners();
  }

  /// Reloads just the signed-in customer's own-review/eligibility state -
  /// used when auth state itself changes (sign in/out) rather than the
  /// whole product-scoped page. Guarded by the same generation counter as
  /// [_load] so it can never clobber a newer full load's result if the two
  /// race (e.g. signing out mid-load).
  Future<void> _loadOwnStateStandalone() async {
    final generation = _loadGeneration;
    final ownState = await _fetchOwnState();
    if (generation != _loadGeneration) return; // superseded, discard
    _myReview = ownState.myReview;
    _isEligibleToReview = ownState.isEligible;
    notifyListeners();
  }

  Future<_OwnReviewState> _fetchOwnState() async {
    if (!_authSessionState.isAuthenticated) {
      return const _OwnReviewState(myReview: null, isEligible: false);
    }
    try {
      final myReview = await _repository.myReviewFor(productId);
      final eligible = await _repository.isEligibleToReview(productId);
      return _OwnReviewState(myReview: myReview, isEligible: eligible);
    } catch (_) {
      // Own-state failing must never block the public review list/aggregate
      // from rendering - fails closed to "no review, not eligible".
      return const _OwnReviewState(myReview: null, isEligible: false);
    }
  }

  /// Re-runs the initial load (list + aggregate + own state) from scratch -
  /// pull-to-refresh.
  Future<void> refresh() => _load();

  /// Switches sort order and reloads the first page. A no-op if [newSort]
  /// is already the current sort.
  Future<void> changeSort(ReviewSortOption newSort) async {
    if (newSort == _sort) return;
    _sort = newSort;
    _cursor = null;
    _hasMore = false;
    await _load();
  }

  /// Fetches the next page and appends it. A no-op while a load/loadMore is
  /// already in flight, or once [hasMore] is `false` - never issues an
  /// overlapping or redundant request.
  Future<void> loadMore() async {
    if (_isLoadingMore || _isLoading || !_hasMore) return;
    _isLoadingMore = true;
    notifyListeners();
    try {
      final page = await _repository.fetchReviews(
        productId: productId,
        sort: _sort,
        cursor: _cursor,
        pageSize: _pageSize,
      );
      _reviews = [..._reviews, ...page.reviews];
      _cursor = page.nextCursor;
      _hasMore = page.hasMore;
    } catch (_) {
      // Leave the list as-is - the customer can retry "load more".
    } finally {
      _isLoadingMore = false;
      notifyListeners();
    }
  }

  /// Creates or edits the signed-in customer's own review for [productId].
  /// Returns `null` on success (and refreshes the aggregate/own-state/first
  /// page so the new/edited review is immediately reflected), or a clean,
  /// `AppToast`-ready error message on failure. Refused with [_busyMessage]
  /// if a submit is already in flight for this product - never fires a
  /// second overlapping request from a double-tap.
  Future<String?> submitReview({
    required int rating,
    String? title,
    required String body,
  }) async {
    if (_isSubmitting) return _busyMessage;
    _isSubmitting = true;
    notifyListeners();
    try {
      final error = await _repository.submitReview(
        productId: productId,
        rating: rating,
        title: title,
        body: body,
      );
      if (error == null) {
        await _refreshAfterMutation();
      }
      return error;
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }

  /// Deletes the signed-in customer's own review. A no-op success if they
  /// don't currently have one. Returns `null` on success or a clean error
  /// message; refused with [_busyMessage] while already in flight.
  Future<String?> deleteReview() async {
    if (_isDeleting) return _busyMessage;
    if (_myReview == null) return null;
    _isDeleting = true;
    notifyListeners();
    try {
      final error = await _repository.deleteReview(productId);
      if (error == null) {
        _myReview = null;
        await _refreshAfterMutation();
      }
      return error;
    } finally {
      _isDeleting = false;
      notifyListeners();
    }
  }

  /// Reports someone else's review. Per-review in-flight guard (a customer
  /// could in principle report two different reviews at once - only a
  /// repeat tap on the SAME review is refused). Returns `null` on success
  /// (including the harmless "already reported" no-op - the repository
  /// never distinguishes it from a first report, matching v1 §0 decision 10)
  /// or a clean error message.
  Future<String?> reportReview({
    required String reviewId,
    required ReviewReportReason reason,
    String? note,
  }) async {
    if (_reportingReviewIds.contains(reviewId)) return _busyMessage;
    _reportingReviewIds.add(reviewId);
    notifyListeners();
    try {
      return await _repository.reportReview(
        reviewId: reviewId,
        reason: reason,
        note: note,
      );
    } finally {
      _reportingReviewIds.remove(reviewId);
      notifyListeners();
    }
  }

  /// A successful submit/delete changes the aggregate, the customer's own
  /// review state, AND (since the default sort is newest-first) very likely
  /// the first page itself - reload all three rather than trying to patch
  /// the in-memory list piecemeal, which risks drifting from the
  /// server-computed aggregate/order.
  Future<void> _refreshAfterMutation() async {
    await _load();
  }
}

/// Plain result tuple for [ReviewsViewModel._fetchOwnState] - avoids two
/// separate sequential awaits duplicated at each of its two call sites.
class _OwnReviewState {
  final ReviewModel? myReview;
  final bool isEligible;

  const _OwnReviewState({required this.myReview, required this.isEligible});
}
