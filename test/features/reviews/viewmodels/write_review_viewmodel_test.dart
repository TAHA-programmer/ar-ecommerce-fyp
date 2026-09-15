import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/features/reviews/repositories/mock_reviews_repository.dart';
import 'package:twin_ar/features/reviews/viewmodels/write_review_viewmodel.dart';

Future<void> _flush() => Future.delayed(Duration.zero);

const _productId = 'p1';

void main() {
  group('WriteReviewViewModel — loading / pre-fill', () {
    test(
      'starts loading, then resolves with a blank form for a new review',
      () async {
        final mock = MockReviewsRepository(currentUserId: 'u1');
        final viewModel = WriteReviewViewModel(
          repository: mock,
          productId: _productId,
        );

        expect(viewModel.isLoading, true);
        await _flush();

        expect(viewModel.isLoading, false);
        expect(viewModel.isEditing, false);
        expect(viewModel.rating, 0);
        expect(viewModel.title, '');
        expect(viewModel.body, '');
      },
    );

    test('pre-fills rating/title/body from an existing review, and reports '
        'isEditing', () async {
      final mock = MockReviewsRepository(currentUserId: 'u1')
        ..markEligible('u1', _productId);
      await mock.submitReview(
        productId: _productId,
        rating: 4,
        title: 'Pretty good',
        body: 'Solid product, would consider buying it again honestly.',
      );

      final viewModel = WriteReviewViewModel(
        repository: mock,
        productId: _productId,
      );
      await _flush();

      expect(viewModel.isEditing, true);
      expect(viewModel.rating, 4);
      expect(viewModel.title, 'Pretty good');
      expect(
        viewModel.body,
        'Solid product, would consider buying it again honestly.',
      );
    });
  });

  group('WriteReviewViewModel — field setters + validity', () {
    test('setRating/setTitle/setBody update state', () async {
      final mock = MockReviewsRepository(currentUserId: 'u1');
      final viewModel = WriteReviewViewModel(
        repository: mock,
        productId: _productId,
      );
      await _flush();

      viewModel.setRating(5);
      viewModel.setTitle('Great');
      viewModel.setBody('A perfectly good review body for this test case.');

      expect(viewModel.rating, 5);
      expect(viewModel.title, 'Great');
      expect(
        viewModel.body,
        'A perfectly good review body for this test case.',
      );
    });

    test(
      'isValid is false with no rating even if the body is long enough',
      () async {
        final mock = MockReviewsRepository(currentUserId: 'u1');
        final viewModel = WriteReviewViewModel(
          repository: mock,
          productId: _productId,
        );
        await _flush();
        viewModel.setBody('A perfectly good review body for this test case.');

        expect(viewModel.isValid, false);
      },
    );

    test(
      'isValid is false with a too-short body even with a rating set',
      () async {
        final mock = MockReviewsRepository(currentUserId: 'u1');
        final viewModel = WriteReviewViewModel(
          repository: mock,
          productId: _productId,
        );
        await _flush();
        viewModel.setRating(5);
        viewModel.setBody('short');

        expect(viewModel.isValid, false);
      },
    );

    test('isValid is true once rating + a long-enough body are set '
        '(title stays optional)', () async {
      final mock = MockReviewsRepository(currentUserId: 'u1');
      final viewModel = WriteReviewViewModel(
        repository: mock,
        productId: _productId,
      );
      await _flush();
      viewModel.setRating(5);
      viewModel.setBody('A perfectly good review body for this test case.');

      expect(viewModel.isValid, true);
    });
  });

  group('WriteReviewViewModel — submit', () {
    test('submitting an eligible, valid review succeeds', () async {
      final mock = MockReviewsRepository(currentUserId: 'u1')
        ..markEligible('u1', _productId);
      final viewModel = WriteReviewViewModel(
        repository: mock,
        productId: _productId,
      );
      await _flush();
      viewModel.setRating(5);
      viewModel.setBody('A perfectly good review body for this test case.');

      final error = await viewModel.submit();

      expect(error, isNull);
      expect(viewModel.isSubmitting, false);
      final saved = await mock.myReviewFor(_productId);
      expect(saved, isNotNull);
      expect(saved!.rating, 5);
    });

    test('submitting when ineligible surfaces the repository\'s clean '
        'error', () async {
      final mock = MockReviewsRepository(currentUserId: 'u1');
      final viewModel = WriteReviewViewModel(
        repository: mock,
        productId: _productId,
      );
      await _flush();
      viewModel.setRating(5);
      viewModel.setBody('A perfectly good review body for this test case.');

      final error = await viewModel.submit();
      expect(error, 'You can only review products from a delivered order.');
    });

    test('an empty (whitespace-only) title is sent as null, not a blank '
        'string', () async {
      final mock = MockReviewsRepository(currentUserId: 'u1')
        ..markEligible('u1', _productId);
      final viewModel = WriteReviewViewModel(
        repository: mock,
        productId: _productId,
      );
      await _flush();
      viewModel.setRating(4);
      viewModel.setTitle('   ');
      viewModel.setBody('A perfectly good review body for this test case.');

      await viewModel.submit();

      final saved = await mock.myReviewFor(_productId);
      expect(saved!.title, isNull);
    });

    test('a second overlapping submit call is refused while the first is '
        'in flight', () async {
      final mock = MockReviewsRepository(currentUserId: 'u1')
        ..markEligible('u1', _productId);
      final viewModel = WriteReviewViewModel(
        repository: mock,
        productId: _productId,
      );
      await _flush();
      viewModel.setRating(5);
      viewModel.setBody('A perfectly good review body for this test case.');

      // `_isSubmitting` is set synchronously before the first `await`
      // inside `submit`, so calling it twice back-to-back (no `await`
      // between the two calls) deterministically makes the SECOND call see
      // the guard already up.
      final firstSubmit = viewModel.submit();
      final secondSubmit = viewModel.submit();

      expect(
        await secondSubmit,
        'Please wait for the current request to finish.',
      );
      expect(await firstSubmit, isNull);
    });
  });
}
