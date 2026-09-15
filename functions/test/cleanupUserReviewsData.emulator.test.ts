import { beforeEach, describe, expect, it } from "vitest";

import { cleanupReviewsDataForUser } from "../src/cleanupUserReviewsData";
import { clearFirestore, readProductStats, readReview, seedReview, testDb } from "./helpers/emulator";

beforeEach(async () => {
  await clearFirestore();
});

describe("cleanupReviewsDataForUser (Auth user-deletion cleanup, Ratings/Reviews v1 Stage 9)", () => {
  it("hard-deletes every review authored by the user, across every product", async () => {
    await seedReview("alice_p1", { userId: "alice", productId: "p1" });
    await seedReview("alice_p2", { userId: "alice", productId: "p2" });

    await cleanupReviewsDataForUser("alice");

    expect(await readReview("alice_p1")).toBeUndefined();
    expect(await readReview("alice_p2")).toBeUndefined();
  });

  it("reverses a PUBLISHED review's rating out of productStats", async () => {
    await testDb.doc("productStats/p1").set({
      ratingSum: 9,
      ratingCount: 2,
      averageRating: 4.5,
      rating4Count: 1,
      rating5Count: 1,
    });
    await seedReview("alice_p1", {
      userId: "alice",
      productId: "p1",
      rating: 5,
      status: "published",
    });

    await cleanupReviewsDataForUser("alice");

    const stats = await readProductStats("p1");
    expect(stats?.ratingSum).toBe(4);
    expect(stats?.ratingCount).toBe(1);
    expect(stats?.rating5Count).toBe(0);
    expect(stats?.rating4Count).toBe(1);
    expect(stats?.averageRating).toBe(4);
  });

  it("does NOT reverse the aggregate for a hidden/rejected review - it was never counted, so deleting it must not double-subtract", async () => {
    await testDb.doc("productStats/p1").set({
      ratingSum: 4,
      ratingCount: 1,
      averageRating: 4,
      rating4Count: 1,
    });
    await seedReview("alice_p1", {
      userId: "alice",
      productId: "p1",
      rating: 2,
      status: "hidden",
    });

    await cleanupReviewsDataForUser("alice");

    const stats = await readProductStats("p1");
    expect(stats?.ratingSum).toBe(4);
    expect(stats?.ratingCount).toBe(1);
  });

  it("deletes reviews of every status for the user, not just published ones", async () => {
    await seedReview("alice_p1", { userId: "alice", productId: "p1", status: "published" });
    await seedReview("alice_p2", { userId: "alice", productId: "p2", status: "hidden" });
    await seedReview("alice_p3", { userId: "alice", productId: "p3", status: "rejected" });

    await cleanupReviewsDataForUser("alice");

    expect(await readReview("alice_p1")).toBeUndefined();
    expect(await readReview("alice_p2")).toBeUndefined();
    expect(await readReview("alice_p3")).toBeUndefined();
  });

  it("never touches another user's reviews or their product's aggregate", async () => {
    await testDb.doc("productStats/p1").set({
      ratingSum: 5,
      ratingCount: 1,
      averageRating: 5,
      rating5Count: 1,
    });
    await seedReview("bob_p1", {
      userId: "bob",
      productId: "p1",
      rating: 5,
      status: "published",
    });

    await cleanupReviewsDataForUser("alice"); // alice has no reviews at all

    expect(await readReview("bob_p1")).toBeDefined();
    const stats = await readProductStats("p1");
    expect(stats?.ratingCount).toBe(1);
    expect(stats?.ratingSum).toBe(5);
  });

  it("is safe to call for a user with no reviews at all", async () => {
    await expect(cleanupReviewsDataForUser("nobody")).resolves.toBeUndefined();
  });

  it("is idempotent - calling it a second time (e.g. a retried trigger) is a harmless no-op", async () => {
    await testDb.doc("productStats/p1").set({
      ratingSum: 5,
      ratingCount: 1,
      averageRating: 5,
      rating5Count: 1,
    });
    await seedReview("alice_p1", {
      userId: "alice",
      productId: "p1",
      rating: 5,
      status: "published",
    });

    await cleanupReviewsDataForUser("alice");
    await cleanupReviewsDataForUser("alice"); // second run - nothing left to do

    expect(await readReview("alice_p1")).toBeUndefined();
    const stats = await readProductStats("p1");
    expect(stats?.ratingCount).toBe(0);
    expect(stats?.ratingSum).toBe(0);
  });

  it("correctly reverses multiple published reviews across distinct products in one sweep", async () => {
    await testDb.doc("productStats/p1").set({
      ratingSum: 5,
      ratingCount: 1,
      averageRating: 5,
      rating5Count: 1,
    });
    await testDb.doc("productStats/p2").set({
      ratingSum: 3,
      ratingCount: 1,
      averageRating: 3,
      rating3Count: 1,
    });
    await seedReview("alice_p1", { userId: "alice", productId: "p1", rating: 5, status: "published" });
    await seedReview("alice_p2", { userId: "alice", productId: "p2", rating: 3, status: "published" });

    await cleanupReviewsDataForUser("alice");

    const stats1 = await readProductStats("p1");
    const stats2 = await readProductStats("p2");
    expect(stats1?.ratingCount).toBe(0);
    expect(stats1?.ratingSum).toBe(0);
    expect(stats2?.ratingCount).toBe(0);
    expect(stats2?.ratingSum).toBe(0);
  });
});
