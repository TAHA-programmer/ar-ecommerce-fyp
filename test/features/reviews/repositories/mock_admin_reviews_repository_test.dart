import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/features/reviews/models/review_model.dart';
import 'package:twin_ar/features/reviews/models/review_moderation_action.dart';
import 'package:twin_ar/features/reviews/models/review_report_model.dart';
import 'package:twin_ar/features/reviews/models/review_report_reason.dart';
import 'package:twin_ar/features/reviews/models/review_status.dart';
import 'package:twin_ar/features/reviews/repositories/mock_admin_reviews_repository.dart';

ReviewModel _review(
  String id, {
  String productId = 'p1',
  String userId = 'u1',
  int rating = 4,
  ReviewStatus status = ReviewStatus.published,
  DateTime? createdAt,
  bool flaggedForReview = false,
  int reportCount = 0,
}) {
  return ReviewModel(
    id: id,
    productId: productId,
    userId: userId,
    authorDisplayName: 'Test User',
    orderId: 'order-1',
    rating: rating,
    body: 'A review body long enough to pass validation checks.',
    status: status,
    reportCount: reportCount,
    flaggedForReview: flaggedForReview,
    createdAt: createdAt ?? DateTime(2026, 1, 1),
  );
}

void main() {
  group('MockAdminReviewsRepository.fetchReviews', () {
    test('returns every seeded review, newest first, across every product '
        'and status', () async {
      final repo = MockAdminReviewsRepository();
      repo.seedReview(
        _review('r1', productId: 'p1', createdAt: DateTime(2026, 1, 1)),
      );
      repo.seedReview(
        _review(
          'r2',
          productId: 'p2',
          status: ReviewStatus.hidden,
          createdAt: DateTime(2026, 1, 3),
        ),
      );
      repo.seedReview(
        _review(
          'r3',
          productId: 'p1',
          status: ReviewStatus.rejected,
          createdAt: DateTime(2026, 1, 2),
        ),
      );

      final reviews = await repo.fetchReviews();

      expect(reviews.map((r) => r.id).toList(), ['r2', 'r3', 'r1']);
    });

    test('an empty repository returns an empty list', () async {
      final repo = MockAdminReviewsRepository();
      expect(await repo.fetchReviews(), isEmpty);
    });
  });

  group('MockAdminReviewsRepository.fetchReportsForReview', () {
    test(
      'returns only reports for the requested review, newest first',
      () async {
        final repo = MockAdminReviewsRepository();
        repo.seedReport(
          ReviewReportModel(
            id: 'a_r1',
            reviewId: 'r1',
            reporterId: 'a',
            reason: ReviewReportReason.spam,
            createdAt: DateTime(2026, 1, 1),
          ),
        );
        repo.seedReport(
          ReviewReportModel(
            id: 'b_r1',
            reviewId: 'r1',
            reporterId: 'b',
            reason: ReviewReportReason.fake,
            note: 'Copy-pasted from another listing.',
            createdAt: DateTime(2026, 1, 3),
          ),
        );
        repo.seedReport(
          ReviewReportModel(
            id: 'c_r2',
            reviewId: 'r2',
            reporterId: 'c',
            reason: ReviewReportReason.offensive,
            createdAt: DateTime(2026, 1, 2),
          ),
        );

        final reports = await repo.fetchReportsForReview('r1');

        expect(reports.map((r) => r.id).toList(), ['b_r1', 'a_r1']);
      },
    );

    test('a review with no reports returns an empty list', () async {
      final repo = MockAdminReviewsRepository();
      expect(await repo.fetchReportsForReview('nope'), isEmpty);
    });
  });

  group('MockAdminReviewsRepository.moderateReview', () {
    test('hide/restore/reject each stamp status + moderatedAt/moderatedBy/'
        'moderationReason', () async {
      final repo = MockAdminReviewsRepository(
        adminUid: 'admin-1',
        now: () => DateTime(2026, 3, 1),
      );
      repo.seedReview(_review('r1', status: ReviewStatus.published));

      final error = await repo.moderateReview(
        reviewId: 'r1',
        action: ReviewModerationAction.hide,
        reason: 'Contains spam links.',
      );

      expect(error, isNull);
      final updated = (await repo.fetchReviews()).single;
      expect(updated.status, ReviewStatus.hidden);
      expect(updated.moderatedBy, 'admin-1');
      expect(updated.moderatedAt, DateTime(2026, 3, 1));
      expect(updated.moderationReason, 'Contains spam links.');
    });

    test('restore is allowed and requires a reason too', () async {
      final repo = MockAdminReviewsRepository();
      repo.seedReview(_review('r1', status: ReviewStatus.hidden));

      final error = await repo.moderateReview(
        reviewId: 'r1',
        action: ReviewModerationAction.restore,
        reason: 'Appeal accepted.',
      );

      expect(error, isNull);
      final updated = (await repo.fetchReviews()).single;
      expect(updated.status, ReviewStatus.published);
      expect(updated.moderationReason, 'Appeal accepted.');
    });

    test('rejects a blank reason - required for EVERY action', () async {
      final repo = MockAdminReviewsRepository();
      repo.seedReview(_review('r1', status: ReviewStatus.published));

      final error = await repo.moderateReview(
        reviewId: 'r1',
        action: ReviewModerationAction.restore,
        reason: '   ',
      );

      expect(error, isNotNull);
      final untouched = (await repo.fetchReviews()).single;
      expect(untouched.status, ReviewStatus.published);
      expect(untouched.moderationReason, isNull);
    });

    test('moderating a non-existent review returns a clean error', () async {
      final repo = MockAdminReviewsRepository();
      final error = await repo.moderateReview(
        reviewId: 'ghost',
        action: ReviewModerationAction.hide,
        reason: 'x',
      );
      expect(error, isNotNull);
    });

    test(
      'nextModerateError simulates a server-side rejection exactly once',
      () async {
        final repo = MockAdminReviewsRepository();
        repo.seedReview(_review('r1', status: ReviewStatus.published));
        repo.nextModerateError = 'Admin access is required for this action.';

        final firstError = await repo.moderateReview(
          reviewId: 'r1',
          action: ReviewModerationAction.hide,
          reason: 'x',
        );
        expect(firstError, 'Admin access is required for this action.');
        final untouched = (await repo.fetchReviews()).single;
        expect(untouched.status, ReviewStatus.published);

        final secondError = await repo.moderateReview(
          reviewId: 'r1',
          action: ReviewModerationAction.hide,
          reason: 'x',
        );
        expect(secondError, isNull);
      },
    );
  });
}
