import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:twin_ar/app/routes/route_names.dart';
import 'package:twin_ar/app/viewmodels/auth_session_state.dart';
import 'package:twin_ar/core/models/auth/auth_result.dart';
import 'package:twin_ar/core/models/auth/user_role.dart';
import 'package:twin_ar/features/reviews/repositories/mock_reviews_repository.dart';
import 'package:twin_ar/features/reviews/viewmodels/reviews_viewmodel.dart';
import 'package:twin_ar/features/reviews/widgets/review_write_entry.dart';

const _productId = 'p1';

AuthSessionState _session(String uid) {
  final s = AuthSessionState();
  s.setSession(
    AuthResult.success(
      userId: uid,
      email: '$uid@x.com',
      role: UserRole.customer,
    ),
  );
  return s;
}

Widget _createWidget(MockReviewsRepository repo, {String uid = 'u1'}) {
  return MaterialApp(
    home: Scaffold(
      body: ChangeNotifierProvider<ReviewsViewModel>(
        create: (_) => ReviewsViewModel(
          repository: repo,
          authSessionState: _session(uid),
          productId: _productId,
        ),
        child: const ReviewWriteEntry(productTitle: 'Test Product'),
      ),
    ),
    routes: {
      RouteNames.writeReview: (_) =>
          const Scaffold(body: Text('Write Review Screen')),
    },
  );
}

void main() {
  group('ReviewWriteEntry', () {
    testWidgets('renders nothing while own-state is still loading', (
      tester,
    ) async {
      final repo = MockReviewsRepository(currentUserId: 'u1')
        ..markEligible('u1', _productId);
      await tester.pumpWidget(_createWidget(repo));
      // Before any pump/settle, the ViewModel's own-state hasn't resolved.
      expect(find.text('Write a Review'), findsNothing);
      expect(find.text('Edit Your Review'), findsNothing);
    });

    testWidgets('renders nothing once loaded if the customer is not '
        'eligible', (tester) async {
      final repo = MockReviewsRepository(currentUserId: 'u1');
      await tester.pumpWidget(_createWidget(repo));
      await tester.pumpAndSettle();

      expect(find.text('Write a Review'), findsNothing);
      expect(find.text('Edit Your Review'), findsNothing);
    });

    testWidgets('shows "Write a Review" for an eligible customer with no '
        'existing review', (tester) async {
      final repo = MockReviewsRepository(currentUserId: 'u1')
        ..markEligible('u1', _productId);
      await tester.pumpWidget(_createWidget(repo));
      await tester.pumpAndSettle();

      expect(find.text('Write a Review'), findsOneWidget);
      expect(find.text('Edit Your Review'), findsNothing);
    });

    testWidgets('shows "Edit Your Review" once the customer already has '
        'one', (tester) async {
      final repo = MockReviewsRepository(currentUserId: 'u1')
        ..markEligible('u1', _productId);
      await repo.submitReview(
        productId: _productId,
        rating: 4,
        body: 'An existing review long enough to satisfy validation here.',
      );
      await tester.pumpWidget(_createWidget(repo));
      await tester.pumpAndSettle();

      expect(find.text('Edit Your Review'), findsOneWidget);
      expect(find.text('Write a Review'), findsNothing);
    });

    testWidgets('tapping the button navigates to the Write Review screen', (
      tester,
    ) async {
      final repo = MockReviewsRepository(currentUserId: 'u1')
        ..markEligible('u1', _productId);
      await tester.pumpWidget(_createWidget(repo));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Write a Review'));
      await tester.pumpAndSettle();

      expect(find.text('Write Review Screen'), findsOneWidget);
    });
  });
}
