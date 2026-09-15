// ignore_for_file: prefer_initializing_formals
import 'package:flutter/foundation.dart';

import '../models/review_model.dart';
import '../models/review_validation.dart';
import '../repositories/reviews_repository.dart';

/// Drives the Write/Edit Review screen (Ratings/Reviews v1 Stage 7) for one
/// `productId` - loads the signed-in customer's existing review (if any) to
/// pre-fill the form as an edit, then submits via the SAME
/// `ReviewsRepository.submitReview` Stage 5 already wires to the
/// `submitReview` callable. Deliberately does NOT re-check eligibility on
/// load: both entry points that reach this screen (Product Details'
/// eligibility-gated "Write a Review" button, and Order Detail's per-item
/// "Rate this product" on an already-known-delivered order) already
/// established eligibility in their own context before navigating here, and
/// the real, authoritative gate is `submitReview`'s own server-side
/// re-verification regardless - re-checking here would just be a redundant
/// read with no additional safety.
class WriteReviewViewModel extends ChangeNotifier {
  final ReviewsRepository _repository;
  final String productId;

  WriteReviewViewModel({
    required ReviewsRepository repository,
    required this.productId,
  }) : _repository = repository {
    _loadExisting();
  }

  bool _isLoading = true;
  bool get isLoading => _isLoading;

  ReviewModel? _existingReview;

  /// `true` once an existing review was found to pre-fill from - drives the
  /// screen's "Write a Review" vs "Edit Your Review" framing.
  bool get isEditing => _existingReview != null;

  int _rating = 0;
  int get rating => _rating;

  String _title = '';
  String get title => _title;

  String _body = '';
  String get body => _body;

  bool _isSubmitting = false;
  bool get isSubmitting => _isSubmitting;

  static const String _busyMessage =
      'Please wait for the current request to finish.';

  Future<void> _loadExisting() async {
    _isLoading = true;
    notifyListeners();

    // `myReviewFor` never throws (fails closed to `null`) - a load failure
    // here just means the form opens blank, as if writing a new review;
    // never blocks the screen from rendering.
    final existing = await _repository.myReviewFor(productId);
    _existingReview = existing;
    if (existing != null) {
      _rating = existing.rating;
      _title = existing.title ?? '';
      _body = existing.body;
    }

    _isLoading = false;
    notifyListeners();
  }

  void setRating(int value) {
    if (_rating == value) return;
    _rating = value;
    notifyListeners();
  }

  void setTitle(String value) {
    if (_title == value) return;
    _title = value;
    notifyListeners();
  }

  void setBody(String value) {
    if (_body == value) return;
    _body = value;
    notifyListeners();
  }

  /// `true` once the current rating/title/body would pass the SAME
  /// validation `submitReview` enforces server-side (`ReviewValidation` is
  /// the single source of truth both sides mirror) - drives the submit
  /// button's enabled state so a customer never submits a request the
  /// server is guaranteed to reject.
  bool get isValid =>
      ReviewValidation.isRatingValid(_rating) &&
      ReviewValidation.isTitleValid(_title.trim().isEmpty ? null : _title) &&
      ReviewValidation.isBodyValid(_body.trim());

  /// Submits (creates or edits) the review. Returns `null` on success, or a
  /// clean, `AppToast`-ready error message. Refused with [_busyMessage] if
  /// a submit is already in flight - never fires a second overlapping
  /// request from a double-tap.
  Future<String?> submit() async {
    if (_isSubmitting) return _busyMessage;
    _isSubmitting = true;
    notifyListeners();
    try {
      final trimmedTitle = _title.trim();
      return await _repository.submitReview(
        productId: productId,
        rating: _rating,
        title: trimmedTitle.isEmpty ? null : trimmedTitle,
        body: _body.trim(),
      );
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }
}
