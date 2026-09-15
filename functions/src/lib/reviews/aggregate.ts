/**
 * Pure rating-aggregate math for `productStats/{productId}` (Ratings/Reviews
 * v1 §2/§3). Deliberately separate from any Firestore/Transaction code so
 * the arithmetic itself - the part most worth getting exactly right - is
 * trivially unit-testable without an emulator.
 *
 * Flat fields, matching `productStats`'s EXISTING `unitsSold`/`favoriteCount`
 * convention (`lib/productStats.ts`) - never a nested map.
 */

export interface RatingAggregate {
  ratingSum: number;
  ratingCount: number;
  rating1Count: number;
  rating2Count: number;
  rating3Count: number;
  rating4Count: number;
  rating5Count: number;
}

export const ZERO_RATING_AGGREGATE: RatingAggregate = {
  ratingSum: 0,
  ratingCount: 0,
  rating1Count: 0,
  rating2Count: 0,
  rating3Count: 0,
  rating4Count: 0,
  rating5Count: 0,
};

function numOr0(v: unknown): number {
  return typeof v === "number" && Number.isFinite(v) ? v : 0;
}

/** Reads whatever rating-aggregate fields exist on a `productStats` document
 *  (defensively coerced - a missing/malformed field reads as `0`, never
 *  throws), leaving every OTHER field (`unitsSold`, `favoriteCount`, ...)
 *  untouched by the caller. */
export function ratingAggregateFromStatsData(
  data: Record<string, unknown> | undefined,
): RatingAggregate {
  return {
    ratingSum: numOr0(data?.ratingSum),
    ratingCount: numOr0(data?.ratingCount),
    rating1Count: numOr0(data?.rating1Count),
    rating2Count: numOr0(data?.rating2Count),
    rating3Count: numOr0(data?.rating3Count),
    rating4Count: numOr0(data?.rating4Count),
    rating5Count: numOr0(data?.rating5Count),
  };
}

/**
 * Applies `delta` (`+1` for a new/restored published review, `-1` to
 * reverse an edited/deleted/hidden one) at `rating` (1-5) to `current`.
 * Every resulting field is floored at `0` - defence in depth against an
 * already-corrupt document; a well-formed caller (matched create/reverse
 * pairs) never needs the floor, but this guarantees the aggregate can never
 * go negative even if it does drift.
 */
export function applyRatingDelta(
  current: RatingAggregate,
  rating: number,
  delta: number,
): RatingAggregate {
  const next: RatingAggregate = { ...current };
  next.ratingCount = Math.max(0, current.ratingCount + delta);
  next.ratingSum = Math.max(0, current.ratingSum + rating * delta);
  switch (rating) {
    case 1:
      next.rating1Count = Math.max(0, current.rating1Count + delta);
      break;
    case 2:
      next.rating2Count = Math.max(0, current.rating2Count + delta);
      break;
    case 3:
      next.rating3Count = Math.max(0, current.rating3Count + delta);
      break;
    case 4:
      next.rating4Count = Math.max(0, current.rating4Count + delta);
      break;
    case 5:
      next.rating5Count = Math.max(0, current.rating5Count + delta);
      break;
  }
  return next;
}

/** `ratingSum / ratingCount`, `0` when there are no reviews - never a
 *  divide-by-zero. */
export function averageRatingOf(aggregate: RatingAggregate): number {
  return aggregate.ratingCount > 0 ? aggregate.ratingSum / aggregate.ratingCount : 0;
}

/** The exact flat fields to `set(..., {merge:true})` onto `productStats`. */
export function statsFieldsFromAggregate(aggregate: RatingAggregate): Record<string, number> {
  return {
    ratingSum: aggregate.ratingSum,
    ratingCount: aggregate.ratingCount,
    averageRating: averageRatingOf(aggregate),
    rating1Count: aggregate.rating1Count,
    rating2Count: aggregate.rating2Count,
    rating3Count: aggregate.rating3Count,
    rating4Count: aggregate.rating4Count,
    rating5Count: aggregate.rating5Count,
  };
}
