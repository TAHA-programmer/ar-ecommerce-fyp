import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:twin_ar/app/viewmodels/auth_session_state.dart';
import 'package:twin_ar/features/admin/reviews_moderation/viewmodels/admin_reviews_viewmodel.dart';
import 'package:twin_ar/features/admin/reviews_moderation/views/admin_reviews_view.dart';
import 'package:twin_ar/features/product_details/models/product_detail_model.dart';
import 'package:twin_ar/features/product_details/repositories/product_details_repository.dart';
import 'package:twin_ar/core/models/product/product_category.dart';
import 'package:twin_ar/core/models/product/product_experience_type.dart';
import 'package:twin_ar/core/models/product/product_summary_model.dart';
import 'package:twin_ar/features/reviews/models/review_model.dart';
import 'package:twin_ar/features/reviews/models/review_status.dart';
import 'package:twin_ar/features/reviews/repositories/mock_admin_reviews_repository.dart';

class _FakeProductDetailsRepository implements ProductDetailsRepository {
  @override
  Future<ProductDetailModel> getProductDetails(String productId) async {
    return ProductDetailModel(
      summary: ProductSummaryModel(
        id: productId,
        title: 'Test Product',
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
}

ReviewModel _review(String id, {ReviewStatus status = ReviewStatus.published}) {
  return ReviewModel(
    id: id,
    productId: 'p1',
    userId: 'u_$id',
    authorDisplayName: 'Test User',
    orderId: 'order-1',
    rating: 4,
    body: 'A review body long enough to pass validation checks.',
    status: status,
    createdAt: DateTime(2026, 1, 1),
  );
}

Widget _createWidget(MockAdminReviewsRepository repo) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthSessionState>(
        create: (_) => AuthSessionState(),
      ),
      ChangeNotifierProvider<AdminReviewsViewModel>(
        create: (_) => AdminReviewsViewModel(
          repository: repo,
          productDetailsRepository: _FakeProductDetailsRepository(),
        ),
      ),
    ],
    child: const MaterialApp(home: AdminReviewsView()),
  );
}

void main() {
  testWidgets('shows a loading indicator on the very first frame', (
    tester,
  ) async {
    await tester.pumpWidget(_createWidget(MockAdminReviewsRepository()));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('shows the honest empty state when there are no reviews at '
      'all', (tester) async {
    await tester.pumpWidget(_createWidget(MockAdminReviewsRepository()));
    await tester.pumpAndSettle();

    expect(find.text('No reviews here'), findsOneWidget);
  });

  testWidgets('shows every review once loaded, filterable by status', (
    tester,
  ) async {
    final repo = MockAdminReviewsRepository();
    repo.seedReview(_review('r1', status: ReviewStatus.published));
    repo.seedReview(_review('r2', status: ReviewStatus.hidden));

    await tester.pumpWidget(_createWidget(repo));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('admin_review_card_r1')), findsOneWidget);
    expect(find.byKey(const Key('admin_review_card_r2')), findsOneWidget);

    await tester.tap(find.byKey(const Key('admin_reviews_filter_chip_hidden')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('admin_review_card_r1')), findsNothing);
    expect(find.byKey(const Key('admin_review_card_r2')), findsOneWidget);
  });

  testWidgets('moderating a review through the sheet updates its status in '
      'the list', (tester) async {
    final repo = MockAdminReviewsRepository();
    repo.seedReview(_review('r1', status: ReviewStatus.published));

    await tester.pumpWidget(_createWidget(repo));
    await tester.pumpAndSettle();

    final cardFinder = find.byKey(const Key('admin_review_card_r1'));
    expect(
      find.descendant(of: cardFinder, matching: find.text('Published')),
      findsOneWidget,
    );

    await tester.tap(find.text('Hide Review'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('admin_review_moderation_reason_field')),
      'Contains spam links.',
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const Key('admin_review_moderation_confirm_button')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Review updated.'), findsOneWidget);
    expect(
      find.descendant(of: cardFinder, matching: find.text('Hidden')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: cardFinder, matching: find.text('Published')),
      findsNothing,
    );

    // Drain AppToast's auto-dismiss Timer before the test ends.
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('pull-to-refresh reloads the list', (tester) async {
    final repo = MockAdminReviewsRepository();
    await tester.pumpWidget(_createWidget(repo));
    await tester.pumpAndSettle();
    expect(find.text('No reviews here'), findsOneWidget);

    repo.seedReview(_review('r1'));
    await tester.fling(
      find.byType(RefreshIndicator),
      const Offset(0, 300),
      1000,
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('admin_review_card_r1')), findsOneWidget);
  });
}
