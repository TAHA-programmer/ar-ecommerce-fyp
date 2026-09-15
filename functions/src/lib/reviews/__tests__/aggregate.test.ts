import { describe, expect, it } from "vitest";

import {
  applyRatingDelta,
  averageRatingOf,
  ratingAggregateFromStatsData,
  statsFieldsFromAggregate,
  ZERO_RATING_AGGREGATE,
} from "../aggregate";

describe("ratingAggregateFromStatsData", () => {
  it("reads all zero for an undefined/empty document (a product with no "
    + "rating fields yet, e.g. one only ever touched by favoriteCount)", () => {
    expect(ratingAggregateFromStatsData(undefined)).toEqual(ZERO_RATING_AGGREGATE);
    expect(ratingAggregateFromStatsData({})).toEqual(ZERO_RATING_AGGREGATE);
  });

  it("ignores unrelated productStats fields (unitsSold, favoriteCount)", () => {
    const result = ratingAggregateFromStatsData({
      unitsSold: 40,
      favoriteCount: 12,
      ratingSum: 8,
      ratingCount: 2,
      rating4Count: 1,
      rating5Count: 1,
    });
    expect(result.ratingSum).toBe(8);
    expect(result.ratingCount).toBe(2);
    expect(result.rating4Count).toBe(1);
    expect(result.rating5Count).toBe(1);
  });

  it("coerces a malformed field to 0 rather than throwing", () => {
    const result = ratingAggregateFromStatsData({
      ratingSum: "not a number",
      ratingCount: null,
    });
    expect(result.ratingSum).toBe(0);
    expect(result.ratingCount).toBe(0);
  });
});

describe("applyRatingDelta", () => {
  it("a +1 at rating 4 increments count, sum, and the 4-star bucket only", () => {
    const result = applyRatingDelta(ZERO_RATING_AGGREGATE, 4, 1);
    expect(result.ratingCount).toBe(1);
    expect(result.ratingSum).toBe(4);
    expect(result.rating4Count).toBe(1);
    expect(result.rating1Count).toBe(0);
    expect(result.rating5Count).toBe(0);
  });

  it("create then reverse the SAME rating returns exactly to zero", () => {
    const created = applyRatingDelta(ZERO_RATING_AGGREGATE, 5, 1);
    const reversed = applyRatingDelta(created, 5, -1);
    expect(reversed).toEqual(ZERO_RATING_AGGREGATE);
  });

  it("an edit (reverse old, apply new) never double-counts", () => {
    const created = applyRatingDelta(ZERO_RATING_AGGREGATE, 2, 1);
    const reversedOld = applyRatingDelta(created, 2, -1);
    const editedTo5 = applyRatingDelta(reversedOld, 5, 1);
    expect(editedTo5.ratingCount).toBe(1);
    expect(editedTo5.ratingSum).toBe(5);
    expect(editedTo5.rating2Count).toBe(0);
    expect(editedTo5.rating5Count).toBe(1);
  });

  it("never goes negative even if the input is already corrupt (defence in "
    + "depth, not a scenario a correct caller should ever produce)", () => {
    const result = applyRatingDelta(ZERO_RATING_AGGREGATE, 3, -1);
    expect(result.ratingCount).toBe(0);
    expect(result.ratingSum).toBe(0);
    expect(result.rating3Count).toBe(0);
  });

  it("multiple products' worth of deltas accumulate correctly", () => {
    let agg = ZERO_RATING_AGGREGATE;
    agg = applyRatingDelta(agg, 5, 1);
    agg = applyRatingDelta(agg, 5, 1);
    agg = applyRatingDelta(agg, 1, 1);
    expect(agg.ratingCount).toBe(3);
    expect(agg.ratingSum).toBe(11);
    expect(agg.rating5Count).toBe(2);
    expect(agg.rating1Count).toBe(1);
  });
});

describe("averageRatingOf", () => {
  it("is 0 for no reviews (never a divide-by-zero)", () => {
    expect(averageRatingOf(ZERO_RATING_AGGREGATE)).toBe(0);
  });

  it("divides sum by count", () => {
    const agg = applyRatingDelta(applyRatingDelta(ZERO_RATING_AGGREGATE, 4, 1), 2, 1);
    expect(averageRatingOf(agg)).toBe(3);
  });
});

describe("statsFieldsFromAggregate", () => {
  it("includes averageRating alongside every flat field", () => {
    const agg = applyRatingDelta(ZERO_RATING_AGGREGATE, 4, 1);
    const fields = statsFieldsFromAggregate(agg);
    expect(fields).toEqual({
      ratingSum: 4,
      ratingCount: 1,
      averageRating: 4,
      rating1Count: 0,
      rating2Count: 0,
      rating3Count: 0,
      rating4Count: 1,
      rating5Count: 0,
    });
  });
});
