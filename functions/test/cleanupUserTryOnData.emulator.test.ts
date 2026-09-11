import { beforeEach, describe, expect, it } from "vitest";
import { Timestamp } from "firebase-admin/firestore";

import { cleanupTryOnDataForUser } from "../src/cleanupUserTryOnData";
import { clearFirestore, storageObjectExists, testDb, uploadTestObject } from "./helpers/emulator";

const BYTES = Buffer.from("x");

beforeEach(async () => {
  await clearFirestore();
});

describe("cleanupTryOnDataForUser (Auth user-deletion cleanup, Phase 9.3 Stage 4)", () => {
  it("deletes the user's tryOnQuota document", async () => {
    await testDb.doc("tryOnQuota/alice").set({ hourCount: 3, dayCount: 3 });
    await cleanupTryOnDataForUser("alice");
    expect((await testDb.doc("tryOnQuota/alice").get()).exists).toBe(false);
  });

  it("deletes every tryOnSessions document owned by the user, and their Storage objects", async () => {
    const resultPath = "users/alice/tryOnResults/s1.jpg";
    const uploadPath = "users/alice/tryOnUploads/s1.jpg";
    await uploadTestObject(resultPath, BYTES, "image/png");
    await uploadTestObject(uploadPath, BYTES, "image/jpeg");
    await testDb.doc("tryOnSessions/s1").set({
      userId: "alice",
      status: "succeeded",
      resultPath,
      expiresAt: Timestamp.fromMillis(Date.now() + 999_999),
    });

    await cleanupTryOnDataForUser("alice");

    expect((await testDb.doc("tryOnSessions/s1").get()).exists).toBe(false);
    expect(await storageObjectExists(resultPath)).toBe(false);
    expect(await storageObjectExists(uploadPath)).toBe(false);
  });

  it("removes a stray Storage object under the user's prefix even with no matching session doc", async () => {
    const strayPath = "users/alice/tryOnResults/orphan.jpg";
    await uploadTestObject(strayPath, BYTES, "image/png");
    await cleanupTryOnDataForUser("alice");
    expect(await storageObjectExists(strayPath)).toBe(false);
  });

  it("never touches another user's sessions, quota, or Storage objects", async () => {
    await testDb.doc("tryOnQuota/bob").set({ hourCount: 1, dayCount: 1 });
    const bobResultPath = "users/bob/tryOnResults/s2.jpg";
    await uploadTestObject(bobResultPath, BYTES, "image/png");
    await testDb.doc("tryOnSessions/s2").set({
      userId: "bob",
      status: "succeeded",
      resultPath: bobResultPath,
      expiresAt: Timestamp.fromMillis(Date.now() + 999_999),
    });

    await cleanupTryOnDataForUser("alice"); // alice has no data at all

    expect((await testDb.doc("tryOnQuota/bob").get()).exists).toBe(true);
    expect((await testDb.doc("tryOnSessions/s2").get()).exists).toBe(true);
    expect(await storageObjectExists(bobResultPath)).toBe(true);
  });

  it("is safe to call for a user with no try-on data at all", async () => {
    await expect(cleanupTryOnDataForUser("nobody")).resolves.toBeUndefined();
  });

  // 2026-09-11 hardening pass (issue #3): never trust a stored `resultPath`
  // field as the delete target - always derive both candidate paths from
  // `(uid, sessionId)` and delete only those.
  it("deletes the result at the DERIVED path even when the stored resultPath field is wrong/foreign", async () => {
    const derivedPath = "users/alice/tryOnResults/s3.jpg";
    await uploadTestObject(derivedPath, BYTES, "image/jpeg");
    await testDb.doc("tryOnSessions/s3").set({
      userId: "alice",
      status: "succeeded",
      resultPath: "users/mallory/tryOnResults/hijacked.jpg", // a bogus/foreign stored value
      expiresAt: Timestamp.fromMillis(Date.now() + 999_999),
    });

    await cleanupTryOnDataForUser("alice");

    expect(await storageObjectExists(derivedPath)).toBe(false);
  });

  it("never deletes another user's object even if the stored resultPath field claims to point there", async () => {
    const foreignPath = "users/mallory/tryOnResults/should-never-be-touched.jpg";
    await uploadTestObject(foreignPath, BYTES, "image/jpeg");
    await testDb.doc("tryOnSessions/s4").set({
      userId: "alice",
      status: "succeeded",
      resultPath: foreignPath,
      expiresAt: Timestamp.fromMillis(Date.now() + 999_999),
    });

    await cleanupTryOnDataForUser("alice");

    expect(await storageObjectExists(foreignPath)).toBe(true); // untouched
  });
});
