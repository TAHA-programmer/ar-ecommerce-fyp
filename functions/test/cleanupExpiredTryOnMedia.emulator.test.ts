import { beforeEach, describe, expect, it } from "vitest";
import { Timestamp } from "firebase-admin/firestore";

import {
  sweepExpiredTryOnMedia,
  sweepOrphanedTryOnUploads,
  sweepStuckTryOnSessions,
} from "../src/lib/tryOn/sweep";
import {
  clearFirestore,
  readTryOnSession,
  storageObjectExists,
  testDb,
  uploadTestObject,
} from "./helpers/emulator";

const RESULT_BYTES = Buffer.from("result-bytes");

async function seedSucceededSession(
  sessionId: string,
  uid: string,
  expiresAtMs: number,
  opts: { withUpload?: boolean; withResult?: boolean } = {},
): Promise<{ resultPath: string; uploadPath: string }> {
  const resultPath = `users/${uid}/tryOnResults/${sessionId}.jpg`;
  const uploadPath = `users/${uid}/tryOnUploads/${sessionId}.jpg`;
  await testDb.doc(`tryOnSessions/${sessionId}`).set({
    userId: uid,
    status: "succeeded",
    productId: "p1",
    colorKey: "blue",
    size: null,
    garmentStoragePath: "products/p1/vto/garment-blue-v1.jpg",
    garmentCategory: "top",
    failureReason: null,
    resultPath,
    provider: "gemini",
    providerModel: "gemini-2.5-flash-image",
    idempotencyKey: "k",
    expiresAt: Timestamp.fromMillis(expiresAtMs),
  });
  if (opts.withResult !== false) {
    await uploadTestObject(resultPath, RESULT_BYTES, "image/png");
  }
  if (opts.withUpload) {
    await uploadTestObject(uploadPath, RESULT_BYTES, "image/jpeg");
  }
  return { resultPath, uploadPath };
}

const NOW = 1_700_000_000_000;

beforeEach(async () => {
  await clearFirestore();
});

describe("sweepExpiredTryOnMedia (D4 safety-fallback TTL sweep)", () => {
  it("deletes the result object and marks an expired succeeded session `expired`", async () => {
    const { resultPath } = await seedSucceededSession("s1", "alice", NOW - 1000);
    const summary = await sweepExpiredTryOnMedia({ nowMs: NOW, batchSize: 10 });
    expect(summary.outcomes.expired).toBe(1);
    expect(await storageObjectExists(resultPath)).toBe(false);
    const session = await readTryOnSession("s1");
    expect(session?.status).toBe("expired");
    expect(session?.resultPath).toBeNull();
  });

  it("also deletes a stray leftover upload object as a defensive backstop", async () => {
    const { uploadPath } = await seedSucceededSession("s2", "alice", NOW - 1000, { withUpload: true });
    await sweepExpiredTryOnMedia({ nowMs: NOW, batchSize: 10 });
    expect(await storageObjectExists(uploadPath)).toBe(false);
  });

  it("does NOT touch a succeeded session that has not expired yet", async () => {
    const { resultPath } = await seedSucceededSession("s3", "alice", NOW + 60_000);
    const summary = await sweepExpiredTryOnMedia({ nowMs: NOW, batchSize: 10 });
    expect(summary.scanned).toBe(0);
    expect(await storageObjectExists(resultPath)).toBe(true);
    expect((await readTryOnSession("s3"))?.status).toBe("succeeded");
  });

  it("does not touch a `failed` or `pending` session even if it has an expiresAt-shaped field", async () => {
    await testDb.doc("tryOnSessions/s4").set({
      userId: "alice",
      status: "failed",
      failureReason: "provider_unavailable",
      expiresAt: Timestamp.fromMillis(NOW - 1000),
    });
    const summary = await sweepExpiredTryOnMedia({ nowMs: NOW, batchSize: 10 });
    expect(summary.scanned).toBe(0);
    expect((await readTryOnSession("s4"))?.status).toBe("failed");
  });

  it("is idempotent - re-running after everything is expired does nothing new", async () => {
    await seedSucceededSession("s5", "alice", NOW - 1000);
    await sweepExpiredTryOnMedia({ nowMs: NOW, batchSize: 10 });
    const second = await sweepExpiredTryOnMedia({ nowMs: NOW, batchSize: 10 });
    expect(second.scanned).toBe(0); // already `expired`, not `succeeded` any more
  });

  it("processes a bounded batch and reports hadMore", async () => {
    for (let i = 0; i < 3; i++) {
      await seedSucceededSession(`batch-${i}`, "alice", NOW - 1000);
    }
    const summary = await sweepExpiredTryOnMedia({ nowMs: NOW, batchSize: 2 });
    expect(summary.scanned).toBe(2);
    expect(summary.hadMore).toBe(true);
  });

  it("isolates a per-session failure - one corrupt session does not block the others", async () => {
    await testDb.doc("tryOnSessions/corrupt").set({
      status: "succeeded",
      // no userId - the sweep must not throw for the whole batch
      expiresAt: Timestamp.fromMillis(NOW - 1000),
    });
    await seedSucceededSession("healthy", "alice", NOW - 1000);
    const summary = await sweepExpiredTryOnMedia({ nowMs: NOW, batchSize: 10 });
    expect(summary.outcomes.expired).toBe(1);
    expect((await readTryOnSession("healthy"))?.status).toBe("expired");
  });

  // 2026-09-11 hardening pass (issue #3): the sweep must never trust a
  // stored `resultPath` field as its delete target - always derive the two
  // candidate paths from `(userId, sessionId)` and delete only those.
  it("deletes the result at the DERIVED path even when the stored resultPath field is wrong/foreign", async () => {
    const sessionId = "trust-hardening-1";
    const derivedPath = `users/alice/tryOnResults/${sessionId}.jpg`;
    await testDb.doc(`tryOnSessions/${sessionId}`).set({
      userId: "alice",
      status: "succeeded",
      resultPath: "users/mallory/tryOnResults/hijacked.jpg", // a bogus/foreign stored value
      expiresAt: Timestamp.fromMillis(NOW - 1000),
    });
    await uploadTestObject(derivedPath, RESULT_BYTES, "image/jpeg");
    const summary = await sweepExpiredTryOnMedia({ nowMs: NOW, batchSize: 10 });
    expect(summary.outcomes.expired).toBe(1);
    expect(await storageObjectExists(derivedPath)).toBe(false);
  });

  it("never deletes another user's object even if the stored resultPath field claims to point there", async () => {
    const sessionId = "trust-hardening-2";
    const foreignPath = "users/mallory/tryOnResults/should-never-be-touched.jpg";
    await uploadTestObject(foreignPath, RESULT_BYTES, "image/jpeg");
    await testDb.doc(`tryOnSessions/${sessionId}`).set({
      userId: "alice",
      status: "succeeded",
      resultPath: foreignPath,
      expiresAt: Timestamp.fromMillis(NOW - 1000),
    });
    await sweepExpiredTryOnMedia({ nowMs: NOW, batchSize: 10 });
    expect(await storageObjectExists(foreignPath)).toBe(true); // untouched
  });
});

describe("sweepStuckTryOnSessions (2026-09-11 hardening - issue #2 recovery)", () => {
  const STALE_MS = 5 * 60 * 1000;

  it("marks a session stuck in 'generating' well past the stale threshold as failed", async () => {
    await testDb.doc("tryOnSessions/stuck1").set({
      userId: "alice",
      status: "generating",
      updatedAt: Timestamp.fromMillis(NOW - STALE_MS - 1000),
    });
    const summary = await sweepStuckTryOnSessions({ nowMs: NOW, staleMs: STALE_MS, batchSize: 10 });
    expect(summary.outcomes.recovered).toBe(1);
    const session = await readTryOnSession("stuck1");
    expect(session?.status).toBe("failed");
    expect(session?.failureReason).toBe("stuck_recovered");
  });

  it("marks a session stuck in 'pending' well past the stale threshold as failed too", async () => {
    await testDb.doc("tryOnSessions/stuck-pending").set({
      userId: "alice",
      status: "pending",
      updatedAt: Timestamp.fromMillis(NOW - STALE_MS - 1000),
    });
    const summary = await sweepStuckTryOnSessions({ nowMs: NOW, staleMs: STALE_MS, batchSize: 10 });
    expect(summary.outcomes.recovered).toBe(1);
  });

  it("also cleans up any orphaned result/upload objects for the recovered session", async () => {
    const resultPathJpg = "users/alice/tryOnResults/stuck2.jpg";
    const uploadPath = "users/alice/tryOnUploads/stuck2.jpg";
    await uploadTestObject(resultPathJpg, Buffer.from("x"), "image/jpeg");
    await uploadTestObject(uploadPath, Buffer.from("x"), "image/jpeg");
    await testDb.doc("tryOnSessions/stuck2").set({
      userId: "alice",
      status: "generating",
      updatedAt: Timestamp.fromMillis(NOW - STALE_MS - 1000),
    });
    await sweepStuckTryOnSessions({ nowMs: NOW, staleMs: STALE_MS, batchSize: 10 });
    expect(await storageObjectExists(resultPathJpg)).toBe(false);
    expect(await storageObjectExists(uploadPath)).toBe(false);
  });

  it("does NOT touch a genuinely fresh pending/generating session (still within staleMs)", async () => {
    await testDb.doc("tryOnSessions/fresh1").set({
      userId: "alice",
      status: "pending",
      updatedAt: Timestamp.fromMillis(NOW - 1000),
    });
    const summary = await sweepStuckTryOnSessions({ nowMs: NOW, staleMs: STALE_MS, batchSize: 10 });
    expect(summary.scanned).toBe(1);
    expect(summary.outcomes.skipped).toBe(1);
    expect((await readTryOnSession("fresh1"))?.status).toBe("pending");
  });

  it("does not scan a succeeded/failed/expired session at all", async () => {
    await testDb.doc("tryOnSessions/done1").set({ userId: "alice", status: "succeeded" });
    const summary = await sweepStuckTryOnSessions({ nowMs: NOW, staleMs: STALE_MS, batchSize: 10 });
    expect(summary.scanned).toBe(0);
  });

  it("is idempotent - re-running after recovery does nothing new (already `failed`, not pending/generating)", async () => {
    await testDb.doc("tryOnSessions/stuck3").set({
      userId: "alice",
      status: "pending",
      updatedAt: Timestamp.fromMillis(NOW - STALE_MS - 1000),
    });
    await sweepStuckTryOnSessions({ nowMs: NOW, staleMs: STALE_MS, batchSize: 10 });
    const second = await sweepStuckTryOnSessions({ nowMs: NOW, staleMs: STALE_MS, batchSize: 10 });
    expect(second.scanned).toBe(0);
  });

  it("isolates a per-session failure - a corrupt session (no userId) does not block the others", async () => {
    await testDb.doc("tryOnSessions/corrupt-stuck").set({
      status: "pending",
      updatedAt: Timestamp.fromMillis(NOW - STALE_MS - 1000),
    });
    await testDb.doc("tryOnSessions/healthy-stuck").set({
      userId: "alice",
      status: "pending",
      updatedAt: Timestamp.fromMillis(NOW - STALE_MS - 1000),
    });
    const summary = await sweepStuckTryOnSessions({ nowMs: NOW, staleMs: STALE_MS, batchSize: 10 });
    expect(summary.outcomes.recovered).toBe(2);
    expect((await readTryOnSession("healthy-stuck"))?.status).toBe("failed");
  });
});

describe("sweepOrphanedTryOnUploads (2026-09-11 hardening - Storage-only backstop, no Firestore record needed)", () => {
  it("deletes a person-photo upload older than the orphan threshold, with no session record at all", async () => {
    const path = "users/orphan-test-uid-1/tryOnUploads/deadbeefdeadbeefdeadbeefdeadbeef.jpg";
    await uploadTestObject(path, Buffer.from("orphan"), "image/jpeg");
    const summary = await sweepOrphanedTryOnUploads({
      nowMs: Date.now() + 10_000,
      olderThanMs: 0,
      maxFiles: 1000,
    });
    expect(summary.deleted).toBeGreaterThanOrEqual(1);
    expect(await storageObjectExists(path)).toBe(false);
  });

  it("does not delete an upload younger than the orphan threshold", async () => {
    const path = "users/orphan-test-uid-2/tryOnUploads/cafebabecafebabecafebabecafebabe.jpg";
    await uploadTestObject(path, Buffer.from("fresh"), "image/jpeg");
    await sweepOrphanedTryOnUploads({
      nowMs: Date.now(),
      olderThanMs: 24 * 60 * 60 * 1000,
      maxFiles: 1000,
    });
    expect(await storageObjectExists(path)).toBe(true);
  });

  it("never touches an object outside tryOnUploads/ under the same users/ prefix (e.g. an avatar)", async () => {
    const avatarPath = "users/orphan-test-uid-3/profile/avatar.jpg";
    await uploadTestObject(avatarPath, Buffer.from("avatar"), "image/jpeg");
    await sweepOrphanedTryOnUploads({ nowMs: Date.now() + 10_000, olderThanMs: 0, maxFiles: 1000 });
    expect(await storageObjectExists(avatarPath)).toBe(true);
  });

  it("never touches a tryOnResults object (results have their own TTL sweep, not this one)", async () => {
    const resultPath = "users/orphan-test-uid-4/tryOnResults/shouldstay.jpg";
    await uploadTestObject(resultPath, Buffer.from("result"), "image/jpeg");
    await sweepOrphanedTryOnUploads({ nowMs: Date.now() + 10_000, olderThanMs: 0, maxFiles: 1000 });
    expect(await storageObjectExists(resultPath)).toBe(true);
  });
});
