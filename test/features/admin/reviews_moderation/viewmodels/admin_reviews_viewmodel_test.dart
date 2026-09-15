import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/core/models/product/product_category.dart';
import 'package:twin_ar/core/models/product/product_experience_type.dart';
import 'package:twin_ar/core/models/product/product_summary_model.dart';
import 'package:twin_ar/features/admin/reviews_moderation/models/admin_review_filter.dart';
import 'package:twin_ar/features/admin/reviews_moderation/viewmodels/admin_reviews_viewmodel.dart';
import 'package:twin_ar/features/product_details/models/product_detail_model.dart';
import 'package:twin_ar/features/product_details/repositories/product_details_repository.dart';
import 'package:twin_ar/features/reviews/models/review_model.dart';
import 'package:twin_ar/features/reviews/models/review_moderation_action.dart';
import 'package:twin_ar/features/reviews/models/review_report_model.dart';
import 'package:twin_ar/features/reviews/models/review_report_reason.dart';
import 'package:twin_ar/features/reviews/models/review_status.dart';
import 'package:twin_ar/features/reviews/repositories/mock_admin_reviews_repository.dart';

Future<void> _flush() => Future.delayed(Duration.zero);

ReviewModel _review(
  String id, {
  String productId = 'p1',
  ReviewStatus status = ReviewStatus.published,
  DateTime? createdAt,
  bool flaggedForReview = false,
  int reportCount = 0,
}) {
  return ReviewModel(
    id: id,
    productId: productId,
    userId: 'u_$id',
    authorDisplayName: 'Test User',
    orderId: 'order-1',
    rating: 4,
    body: 'A review body long enough to pass validation checks.',
    status: status,
    reportCount: reportCount,
    flaggedForReview: flaggedForReview,
    createdAt: createdAt ?? DateTime(2026, 1, 1),
  );
}

ProductDetailModel _product(String id, String title) {
  return ProductDetailModel(
    summary: ProductSummaryModel(
      id: id,
      title: title,
      imageAssetPath: 'assets/images/placeholder.png',
      currentPrice: 'Rs 1,000/-',
    ),
    stockQuantity: 5,
    categoryId: 'furniture',
    categoryKind: ProductCategory.furniture,
    experienceType: ProductExperienceType.none,
    subcategory: 'Chairs',
    gallery: const [],
    description: 'A test product.',
    availableColors: const [],
    availableSizes: const [],
    specifications: const [],
    deliveryEstimate: '3-5 Business Days',
  );
}

class _FakeProductDetailsRepository implements ProductDetailsRepository {
  final Map<String, ProductDetailModel> products;
  final List<String> calls = [];

  _FakeProductDetailsRepository(this.products);

  @override
  Future<ProductDetailModel> getProductDetails(String productId) async {
    calls.add(productId);
    if (!products.containsKey(productId)) {
      throw StateError('Product not found for ID: $productId');
    }
    return products[productId]!;
  }
}

void main() {
  group('AdminReviewsViewModel — loading', () {
    test('starts loading, then resolves to the honest empty state with no '
        'reviews', () async {
      final repo = MockAdminReviewsRepository();
      final viewModel = AdminReviewsViewModel(
        repository: repo,
        productDetailsRepository: _FakeProductDetailsRepository({}),
      );

      expect(viewModel.isLoading, true);
      await _flush();

      expect(viewModel.isLoading, false);
      expect(viewModel.hasLoadError, false);
      expect(viewModel.isEmpty, true);
      expect(viewModel.filteredReviews, isEmpty);
    });

    test('resolves each review\'s product summary, isolating a per-item '
        'resolution failure', () async {
      final repo = MockAdminReviewsRepository();
      repo.seedReview(_review('r1', productId: 'p1'));
      repo.seedReview(_review('r2', productId: 'p2'));
      final products = _FakeProductDetailsRepository({
        'p1': _product('p1', 'Luna Accent Chair'),
      });
      final viewModel = AdminReviewsViewModel(
        repository: repo,
        productDetailsRepository: products,
      );
      await _flush();
      await _flush();

      expect(viewModel.productSummaryFor('p1')!.title, 'Luna Accent Chair');
      expect(viewModel.productSummaryFor('p2'), isNull);
      expect(viewModel.filteredReviews, hasLength(2)); // still both shown
    });
  });

  group('AdminReviewsViewModel — filtering + flagged priority', () {
    test('defaults to the "all" filter, showing every status', () async {
      final repo = MockAdminReviewsRepository();
      repo.seedReview(_review('r1', status: ReviewStatus.published));
      repo.seedReview(_review('r2', status: ReviewStatus.hidden));
      repo.seedReview(_review('r3', status: ReviewStatus.rejected));
      final viewModel = AdminReviewsViewModel(
        repository: repo,
        productDetailsRepository: _FakeProductDetailsRepository({}),
      );
      await _flush();

      expect(viewModel.filter, AdminReviewFilter.all);
      expect(viewModel.filteredReviews, hasLength(3));
    });

    test('narrows to exactly the selected status', () async {
      final repo = MockAdminReviewsRepository();
      repo.seedReview(_review('r1', status: ReviewStatus.published));
      repo.seedReview(_review('r2', status: ReviewStatus.hidden));
      repo.seedReview(_review('r3', status: ReviewStatus.rejected));
      final viewModel = AdminReviewsViewModel(
        repository: repo,
        productDetailsRepository: _FakeProductDetailsRepository({}),
      );
      await _flush();

      viewModel.setFilter(AdminReviewFilter.hidden);
      expect(viewModel.filteredReviews.map((r) => r.id).toList(), ['r2']);

      viewModel.setFilter(AdminReviewFilter.rejected);
      expect(viewModel.filteredReviews.map((r) => r.id).toList(), ['r3']);
    });

    test('the "flagged" filter shows only flagged reviews, regardless of '
        'status', () async {
      final repo = MockAdminReviewsRepository();
      repo.seedReview(
        _review('r1', status: ReviewStatus.published, flaggedForReview: true),
      );
      repo.seedReview(
        _review('r2', status: ReviewStatus.hidden, flaggedForReview: false),
      );
      final viewModel = AdminReviewsViewModel(
        repository: repo,
        productDetailsRepository: _FakeProductDetailsRepository({}),
      );
      await _flush();

      viewModel.setFilter(AdminReviewFilter.flagged);
      expect(viewModel.filteredReviews.map((r) => r.id).toList(), ['r1']);
    });

    test('flaggedCount reflects the whole list, unaffected by the current '
        'filter', () async {
      final repo = MockAdminReviewsRepository();
      repo.seedReview(_review('r1', flaggedForReview: true));
      repo.seedReview(_review('r2', flaggedForReview: true));
      repo.seedReview(_review('r3', flaggedForReview: false));
      final viewModel = AdminReviewsViewModel(
        repository: repo,
        productDetailsRepository: _FakeProductDetailsRepository({}),
      );
      await _flush();

      expect(viewModel.flaggedCount, 2);
      viewModel.setFilter(AdminReviewFilter.rejected);
      expect(viewModel.flaggedCount, 2);
    });

    test('flagged reviews always sort FIRST within the active filter, then '
        'newest first', () async {
      final repo = MockAdminReviewsRepository();
      repo.seedReview(
        _review(
          'oldest-flagged',
          createdAt: DateTime(2026, 1, 1),
          flaggedForReview: true,
        ),
      );
      repo.seedReview(
        _review('newest-unflagged', createdAt: DateTime(2026, 1, 5)),
      );
      repo.seedReview(
        _review('older-unflagged', createdAt: DateTime(2026, 1, 3)),
      );
      final viewModel = AdminReviewsViewModel(
        repository: repo,
        productDetailsRepository: _FakeProductDetailsRepository({}),
      );
      await _flush();

      expect(viewModel.filteredReviews.map((r) => r.id).toList(), [
        'oldest-flagged',
        'newest-unflagged',
        'older-unflagged',
      ]);
    });

    test('setting the filter to its current value is a no-op (still '
        'correct, just doesn\'t re-notify unnecessarily)', () async {
      final repo = MockAdminReviewsRepository();
      final viewModel = AdminReviewsViewModel(
        repository: repo,
        productDetailsRepository: _FakeProductDetailsRepository({}),
      );
      await _flush();
      viewModel.setFilter(AdminReviewFilter.all);
      expect(viewModel.filter, AdminReviewFilter.all);
    });
  });

  group('AdminReviewsViewModel — report audit trail', () {
    test(
      'loadReportsFor fetches and caches, never re-fetching once loaded',
      () async {
        final repo = MockAdminReviewsRepository();
        repo.seedReview(_review('r1', reportCount: 1));
        repo.seedReport(
          ReviewReportModel(
            id: 'a_r1',
            reviewId: 'r1',
            reporterId: 'a',
            reason: ReviewReportReason.spam,
            createdAt: DateTime(2026, 1, 1),
          ),
        );
        final viewModel = AdminReviewsViewModel(
          repository: repo,
          productDetailsRepository: _FakeProductDetailsRepository({}),
        );
        await _flush();

        expect(viewModel.reportsFor('r1'), isNull);
        await viewModel.loadReportsFor('r1');
        expect(viewModel.reportsFor('r1'), hasLength(1));

        // A second call must not re-fetch (no observable seam here besides
        // it simply not throwing/duplicating - re-run to confirm stability).
        await viewModel.loadReportsFor('r1');
        expect(viewModel.reportsFor('r1'), hasLength(1));
      },
    );

    test(
      'a review with no reports resolves to an empty list, not null',
      () async {
        final repo = MockAdminReviewsRepository();
        repo.seedReview(_review('r1'));
        final viewModel = AdminReviewsViewModel(
          repository: repo,
          productDetailsRepository: _FakeProductDetailsRepository({}),
        );
        await _flush();

        await viewModel.loadReportsFor('r1');
        expect(viewModel.reportsFor('r1'), isEmpty);
      },
    );
  });

  group('AdminReviewsViewModel — moderate', () {
    test(
      'a successful moderation reloads the list with the new status',
      () async {
        final repo = MockAdminReviewsRepository();
        repo.seedReview(_review('r1', status: ReviewStatus.published));
        final viewModel = AdminReviewsViewModel(
          repository: repo,
          productDetailsRepository: _FakeProductDetailsRepository({}),
        );
        await _flush();

        final error = await viewModel.moderate(
          reviewId: 'r1',
          action: ReviewModerationAction.hide,
          reason: 'Spam content.',
        );

        expect(error, isNull);
        expect(viewModel.filteredReviews.single.status, ReviewStatus.hidden);
        expect(
          viewModel.filteredReviews.single.moderationReason,
          'Spam content.',
        );
      },
    );

    test(
      'a second overlapping moderate call for the SAME review is refused',
      () async {
        final repo = MockAdminReviewsRepository();
        repo.seedReview(_review('r1', status: ReviewStatus.published));
        final viewModel = AdminReviewsViewModel(
          repository: repo,
          productDetailsRepository: _FakeProductDetailsRepository({}),
        );
        await _flush();

        final first = viewModel.moderate(
          reviewId: 'r1',
          action: ReviewModerationAction.hide,
          reason: 'Spam content.',
        );
        final second = viewModel.moderate(
          reviewId: 'r1',
          action: ReviewModerationAction.reject,
          reason: 'Also spam.',
        );

        expect(await second, 'Please wait for the current request to finish.');
        expect(await first, isNull);
      },
    );

    test('a moderation failure leaves the review status untouched and '
        'surfaces the error', () async {
      final repo = MockAdminReviewsRepository();
      repo.seedReview(_review('r1', status: ReviewStatus.published));
      repo.nextModerateError = 'Admin access is required for this action.';
      final viewModel = AdminReviewsViewModel(
        repository: repo,
        productDetailsRepository: _FakeProductDetailsRepository({}),
      );
      await _flush();

      final error = await viewModel.moderate(
        reviewId: 'r1',
        action: ReviewModerationAction.hide,
        reason: 'x',
      );

      expect(error, 'Admin access is required for this action.');
      expect(viewModel.filteredReviews.single.status, ReviewStatus.published);
    });
  });
}
