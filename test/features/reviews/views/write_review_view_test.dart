import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:twin_ar/features/reviews/repositories/mock_reviews_repository.dart';
import 'package:twin_ar/features/reviews/viewmodels/write_review_viewmodel.dart';
import 'package:twin_ar/features/reviews/views/write_review_view.dart';
import 'package:twin_ar/features/reviews/widgets/review_rating_input.dart';

const _productId = 'p1';

Widget _createWidget(MockReviewsRepository repo) {
  return MaterialApp(
    home: ChangeNotifierProvider<WriteReviewViewModel>(
      create: (_) =>
          WriteReviewViewModel(repository: repo, productId: _productId),
      child: const WriteReviewView(productTitle: 'Luna Accent Chair'),
    ),
  );
}

void main() {
  group('WriteReviewView', () {
    testWidgets('shows "Write a Review" title and a disabled submit '
        'button before anything is entered', (tester) async {
      final repo = MockReviewsRepository(currentUserId: 'u1')
        ..markEligible('u1', _productId);
      await tester.pumpWidget(_createWidget(repo));
      await tester.pumpAndSettle();

      expect(find.text('Write a Review'), findsWidgets);
      expect(find.text('Luna Accent Chair'), findsOneWidget);

      final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Submit Review'),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('shows "Edit Your Review" and pre-fills the form for an '
        'existing review', (tester) async {
      final repo = MockReviewsRepository(currentUserId: 'u1')
        ..markEligible('u1', _productId);
      await repo.submitReview(
        productId: _productId,
        rating: 4,
        title: 'Pretty good',
        body: 'Solid product, would consider buying it again honestly.',
      );

      await tester.pumpWidget(_createWidget(repo));
      await tester.pumpAndSettle();

      expect(find.text('Edit Your Review'), findsWidgets);
      expect(find.text('Pretty good'), findsOneWidget);
      expect(
        find.text('Solid product, would consider buying it again honestly.'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(ElevatedButton, 'Update Review'),
        findsOneWidget,
      );
    });

    testWidgets('submit button enables once a rating + valid body are set, '
        'and a successful submit pops back to the caller', (tester) async {
      final repo = MockReviewsRepository(currentUserId: 'u1')
        ..markEligible('u1', _productId);

      await tester.pumpWidget(
        MaterialApp(
          initialRoute: '/root',
          routes: {
            '/root': (_) => const Scaffold(body: Text('Root Screen')),
            '/write-review': (_) =>
                ChangeNotifierProvider<WriteReviewViewModel>(
                  create: (_) => WriteReviewViewModel(
                    repository: repo,
                    productId: _productId,
                  ),
                  child: const WriteReviewView(
                    productTitle: 'Luna Accent Chair',
                  ),
                ),
          },
        ),
      );
      await tester.pumpAndSettle();

      final rootContext = tester.element(find.text('Root Screen'));
      Navigator.pushNamed(rootContext, '/write-review');
      await tester.pumpAndSettle();

      // Tap the 5th star - scoped to ReviewRatingInput so the AppBar's own
      // back-button IconButton (present here since this route was pushed
      // on top of another) can never be confused for one of the 5 stars.
      final starButtons = find.descendant(
        of: find.byType(ReviewRatingInput),
        matching: find.byType(IconButton),
      );
      expect(starButtons, findsNWidgets(5));
      await tester.tap(starButtons.last);
      await tester.pump();

      await tester.enterText(
        find.widgetWithText(TextField, 'Your review'),
        'A perfectly good review body for this test case here.',
      );
      await tester.pump();

      final submitButton = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Submit Review'),
      );
      expect(submitButton.onPressed, isNotNull);

      await tester.tap(find.widgetWithText(ElevatedButton, 'Submit Review'));
      await tester.pumpAndSettle();

      final saved = await repo.myReviewFor(_productId);
      expect(saved, isNotNull);
      expect(saved!.rating, 5);
      // A successful submit pops back to the caller.
      expect(find.text('Root Screen'), findsOneWidget);
      // Drain AppToast's 3s auto-dismiss timer before the test tears down -
      // it holds static state shared across the whole binding, so an
      // un-drained timer here crashes a LATER test's widget tree.
      await tester.pump(const Duration(seconds: 4));
    });
  });
}
