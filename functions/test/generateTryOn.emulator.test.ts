import { beforeEach, describe, expect, it } from "vitest";

import { Timestamp } from "firebase-admin/firestore";

import { generateTryOnHandler } from "../src/generateTryOn";
import { VtoProviderError } from "../src/lib/tryOn/provider";
import { tryOnSessionIdFor } from "../src/lib/tryOn/session";
import {
  clearFirestore,
  makeFakeVtoProvider,
  PNG_RESULT_BYTES,
  readStorageObjectBytes,
  readTryOnGlobalQuota,
  readTryOnSession,
  readTryOnUserQuota,
  seedPersonPhoto,
  seedProduct,
  seedVtoProduct,
  storageObjectExists,
  testDb,
  uploadTestObject,
} from "./helpers/emulator";

const UID = "alice-uid";
const OTHER_UID = "bob-uid";
const PRODUCT_ID = "mens-oxford-shirt";
const COLOR = "blue";
const NOW = 1_700_000_000_000;

function body(overrides: Record<string, unknown> = {}) {
  return {
    productId: PRODUCT_ID,
    colorKey: COLOR,
    size: "M",
    idempotencyKey: `idem-${Math.random().toString(36).slice(2)}-key`,
    consent: true,
    ...overrides,
  };
}

async function call(
  data: Record<string, unknown>,
  opts: {
    uid?: string | undefined;
    provider?: ReturnType<typeof makeFakeVtoProvider>;
    now?: number;
  } = {},
) {
  const fake = opts.provider ?? makeFakeVtoProvider();
  const result = await generateTryOnHandler({
    authUid: "uid" in opts ? opts.uid : UID,
    data,
    provider: fake.provider,
    now: () => opts.now ?? NOW,
  });
  return { result, fake };
}

async function expectAppError(promise: Promise<unknown>, appCode: string) {
  try {
    await promise;
  } catch (err) {
    const details = (err as { details?: Record<string, unknown> }).details ?? {};
    expect(details.appCode, `expected appCode ${appCode}, got: ${JSON.stringify(err)}`).toBe(appCode);
    return err as { code?: string; details?: Record<string, unknown> };
  }
  throw new Error(`expected the call to reject with appCode ${appCode}, but it resolved`);
}

/** Uploads the person photo at the exact deterministic path for this (uid, key). */
async function seedPhotoForKey(uid: string, idempotencyKey: string): Promise<string> {
  const sessionId = tryOnSessionIdFor(uid, idempotencyKey);
  return seedPersonPhoto(uid, sessionId);
}

beforeEach(async () => {
  await clearFirestore();
});

describe("generateTryOn - authentication & input", () => {
  it("rejects an unauthenticated caller", async () => {
    await seedVtoProduct(PRODUCT_ID, COLOR);
    await expectAppError(call(body(), { uid: undefined }), "UNAUTHENTICATED");
  });

  it("rejects a malformed request body", async () => {
    await expectAppError(call({ nonsense: true }), "INVALID_REQUEST");
  });

  it("rejects a request missing consent", async () => {
    await seedVtoProduct(PRODUCT_ID, COLOR);
    await expectAppError(call(body({ consent: false })), "CONSENT_REQUIRED");
  });
});

describe("generateTryOn - product eligibility (no quota spent)", () => {
  it("rejects a missing product", async () => {
    await expectAppError(call(body()), "PRODUCT_UNAVAILABLE");
  });

  it("rejects a draft product", async () => {
    await seedVtoProduct(PRODUCT_ID, COLOR, { publicationStatus: "draft" });
    await expectAppError(call(body()), "PRODUCT_UNAVAILABLE");
  });

  it("rejects a non-VTO product", async () => {
    await seedProduct(PRODUCT_ID, { publicationStatus: "published", isActive: true, experienceType: "none" });
    await expectAppError(call(body()), "PRODUCT_NOT_ELIGIBLE");
  });

  it("rejects when the admin has disabled the VTO entry point", async () => {
    await seedVtoProduct(PRODUCT_ID, COLOR, { vtoDisabled: true });
    await expectAppError(call(body()), "PRODUCT_NOT_ELIGIBLE");
  });

  it("rejects an unavailable colour", async () => {
    await seedVtoProduct(PRODUCT_ID, COLOR);
    await expectAppError(call(body({ colorKey: "purple" })), "VARIANT_UNAVAILABLE");
  });

  it("rejects an unavailable size", async () => {
    await seedVtoProduct(PRODUCT_ID, COLOR);
    await expectAppError(call(body({ size: "XXL" })), "VARIANT_UNAVAILABLE");
  });

  it("rejects a garment asset with a cross-product storage path (ownership defence)", async () => {
    await seedVtoProduct(PRODUCT_ID, COLOR, {}, { storagePath: "products/other-product/vto/garment-blue-v1.jpg" });
    await expectAppError(call(body()), "GARMENT_UNAVAILABLE");
  });

  it("none of these eligibility rejections consume the per-user rate limit", async () => {
    await seedVtoProduct(PRODUCT_ID, COLOR, { vtoDisabled: true });
    await expectAppError(call(body()), "PRODUCT_NOT_ELIGIBLE");
    await expectAppError(call(body()), "PRODUCT_NOT_ELIGIBLE");
    expect(await readTryOnUserQuota(UID)).toBeUndefined();
  });
});

describe("generateTryOn - success path", () => {
  it("generates a preview, writes the result, and deletes the person upload unconditionally (D4)", async () => {
    await seedVtoProduct(PRODUCT_ID, COLOR);
    const key = "success-key-1";
    const uploadPath = await seedPhotoForKey(UID, key);

    const { result, fake } = await call(body({ idempotencyKey: key }));

    expect(result.status).toBe("succeeded");
    expect(result.provider).toBe("gemini");
    expect(fake.calls).toHaveLength(1);

    expect(await storageObjectExists(uploadPath)).toBe(false); // deleted immediately
    expect(await storageObjectExists(result.resultPath)).toBe(true);

    const session = await readTryOnSession(tryOnSessionIdFor(UID, key));
    expect(session?.status).toBe("succeeded");
    expect(session?.userId).toBe(UID);
    expect(session?.resultPath).toBe(result.resultPath);
    expect(session?.consentAt).toBeTruthy();
  });

  it("bumps both the per-user and the global quota counters exactly once", async () => {
    await seedVtoProduct(PRODUCT_ID, COLOR);
    const key = "success-key-quota";
    await seedPhotoForKey(UID, key);
    await call(body({ idempotencyKey: key }));

    const userQuota = await readTryOnUserQuota(UID);
    expect(userQuota?.hourCount).toBe(1);
    expect(userQuota?.dayCount).toBe(1);
    const globalQuota = await readTryOnGlobalQuota();
    expect(globalQuota?.dayCount).toBe(1);
  });

  it("passes the exact person + garment bytes and the size as a soft hint to the provider", async () => {
    await seedVtoProduct(PRODUCT_ID, COLOR);
    const key = "success-key-provider-input";
    await seedPhotoForKey(UID, key);
    const { fake } = await call(body({ idempotencyKey: key, size: "L" }));
    const input = fake.calls[0] as {
      personContentType: string;
      garmentContentType: string;
      garmentCategory: string;
      sizeHint: string | null;
    };
    expect(input.personContentType).toBe("image/jpeg");
    expect(input.garmentContentType).toBe("image/jpeg");
    expect(input.garmentCategory).toBe("top");
    expect(input.sizeHint).toBe("L");
  });
});

describe("generateTryOn - missing / invalid person photo", () => {
  it("fails cleanly when the person photo was never uploaded", async () => {
    await seedVtoProduct(PRODUCT_ID, COLOR);
    const key = "no-photo-key";
    await expectAppError(call(body({ idempotencyKey: key })), "PHOTO_MISSING");
    const session = await readTryOnSession(tryOnSessionIdFor(UID, key));
    expect(session?.status).toBe("failed");
    expect(session?.failureReason).toBe("missing_photo");
  });

  it("rejects an uploaded object with a disallowed content type (defence in depth)", async () => {
    await seedVtoProduct(PRODUCT_ID, COLOR);
    const key = "bad-type-key";
    const sessionId = tryOnSessionIdFor(UID, key);
    await uploadTestObject(`users/${UID}/tryOnUploads/${sessionId}.jpg`, Buffer.from("not-an-image"), "text/plain");
    await expectAppError(call(body({ idempotencyKey: key })), "PHOTO_INVALID");
  });

  it("a failed generation (missing photo) still deletes any person-upload object and never spends the provider call", async () => {
    await seedVtoProduct(PRODUCT_ID, COLOR);
    const key = "no-photo-key-2";
    const { fake } = { fake: makeFakeVtoProvider() };
    await expectAppError(
      generateTryOnHandler({ authUid: UID, data: body({ idempotencyKey: key }), provider: fake.provider, now: () => NOW }),
      "PHOTO_MISSING",
    );
    expect(fake.calls).toHaveLength(0);
  });
});

describe("generateTryOn - garment asset missing from Storage", () => {
  it("fails cleanly when the Firestore-recorded garment object does not actually exist in Storage", async () => {
    // A dedicated product id/colour, never uploaded to by any other test in
    // this file - Storage state (unlike Firestore) is NOT cleared between
    // tests, so reusing PRODUCT_ID/COLOR here would find an object a
    // different test already uploaded to that same path.
    const productId = "garment-missing-product";
    await seedVtoProduct(productId, "green", { skipGarmentUpload: true });
    const key = "garment-missing-key";
    await seedPhotoForKey(UID, key);
    await expectAppError(
      call(body({ productId, colorKey: "green", idempotencyKey: key })),
      "GARMENT_UNAVAILABLE",
    );
  });
});

describe("generateTryOn - provider failure mapping", () => {
  it("maps a safety-block refusal to PROVIDER_REFUSED and marks the session failed", async () => {
    await seedVtoProduct(PRODUCT_ID, COLOR);
    const key = "safety-key";
    await seedPhotoForKey(UID, key);
    const fake = makeFakeVtoProvider({ failWith: new VtoProviderError("safety_block", "blocked") });
    await expectAppError(call(body({ idempotencyKey: key }), { provider: fake }), "PROVIDER_REFUSED");
    const session = await readTryOnSession(tryOnSessionIdFor(UID, key));
    expect(session?.status).toBe("failed");
    expect(session?.failureReason).toBe("provider_refused");
  });

  it("maps a timeout to TIMEOUT", async () => {
    await seedVtoProduct(PRODUCT_ID, COLOR);
    const key = "timeout-key";
    await seedPhotoForKey(UID, key);
    const fake = makeFakeVtoProvider({ failWith: new VtoProviderError("timeout", "timed out") });
    await expectAppError(call(body({ idempotencyKey: key }), { provider: fake }), "TIMEOUT");
  });

  it("maps a network/5xx failure to PROVIDER_UNAVAILABLE", async () => {
    await seedVtoProduct(PRODUCT_ID, COLOR);
    const key = "network-key";
    await seedPhotoForKey(UID, key);
    const fake = makeFakeVtoProvider({ failWith: new VtoProviderError("network", "503") });
    await expectAppError(call(body({ idempotencyKey: key }), { provider: fake }), "PROVIDER_UNAVAILABLE");
  });

  it("deletes the person upload even when the provider call fails", async () => {
    await seedVtoProduct(PRODUCT_ID, COLOR);
    const key = "fail-cleanup-key";
    const uploadPath = await seedPhotoForKey(UID, key);
    const fake = makeFakeVtoProvider({ failWith: new VtoProviderError("network", "503") });
    await expectAppError(call(body({ idempotencyKey: key }), { provider: fake }), "PROVIDER_UNAVAILABLE");
    expect(await storageObjectExists(uploadPath)).toBe(false);
  });

  it("never writes a result object on provider failure", async () => {
    await seedVtoProduct(PRODUCT_ID, COLOR);
    const key = "no-result-key";
    await seedPhotoForKey(UID, key);
    const fake = makeFakeVtoProvider({ failWith: new VtoProviderError("network", "503") });
    await expectAppError(call(body({ idempotencyKey: key }), { provider: fake }), "PROVIDER_UNAVAILABLE");
    const sessionId = tryOnSessionIdFor(UID, key);
    expect(await storageObjectExists(`users/${UID}/tryOnResults/${sessionId}.jpg`)).toBe(false);
  });
});

describe("generateTryOn - idempotency (UC-15 4B: duplicate request not processed twice)", () => {
  it("a retry with the SAME key after success returns the cached result with NO second provider call", async () => {
    await seedVtoProduct(PRODUCT_ID, COLOR);
    const key = "retry-success-key";
    await seedPhotoForKey(UID, key);
    const fake = makeFakeVtoProvider();

    const first = await call(body({ idempotencyKey: key }), { provider: fake });
    expect(fake.calls).toHaveLength(1);

    // A genuine retry never re-uploads a photo (D4 already deleted it) - the
    // handler must still succeed from the cached session, not fail on a
    // missing photo.
    const second = await call(body({ idempotencyKey: key }), { provider: fake });
    expect(second.result.sessionId).toBe(first.result.sessionId);
    expect(second.result.resultPath).toBe(first.result.resultPath);
    expect(fake.calls).toHaveLength(1); // still exactly one provider call
  });

  it("a retry with the SAME key after a failure is refused (SESSION_ATTEMPT_CLOSED) - must mint a new key", async () => {
    await seedVtoProduct(PRODUCT_ID, COLOR);
    const key = "retry-fail-key";
    await seedPhotoForKey(UID, key); // consumed + deleted by the first (failing) attempt
    const fake = makeFakeVtoProvider({ failWith: new VtoProviderError("network", "503") });
    await expectAppError(call(body({ idempotencyKey: key }), { provider: fake }), "PROVIDER_UNAVAILABLE");

    // Second attempt, same key: the provider would now succeed, but the
    // attempt must stay closed - no second provider call is ever made.
    const fake2 = makeFakeVtoProvider();
    await expectAppError(call(body({ idempotencyKey: key }), { provider: fake2 }), "SESSION_ATTEMPT_CLOSED");
    expect(fake2.calls).toHaveLength(0);
  });

  it("a session owned by ANOTHER user at the same derived id is refused (hash-collision / tamper defence)", async () => {
    await seedVtoProduct(PRODUCT_ID, COLOR);
    const key = "foreign-key";
    const sessionId = tryOnSessionIdFor(UID, key);
    await testDb.doc(`tryOnSessions/${sessionId}`).set({
      userId: OTHER_UID,
      status: "pending",
      productId: PRODUCT_ID,
      colorKey: COLOR,
      size: null,
      garmentStoragePath: "x",
      garmentCategory: "top",
      failureReason: null,
      resultPath: null,
      provider: "gemini",
      providerModel: "gemini-2.5-flash-image",
      idempotencyKey: key,
    });
    await expectAppError(call(body({ idempotencyKey: key })), "FORBIDDEN");
  });

  it("a fresh 'in progress' session for the same key is refused rather than double-generating", async () => {
    await seedVtoProduct(PRODUCT_ID, COLOR);
    const key = "in-progress-key";
    const sessionId = tryOnSessionIdFor(UID, key);
    await testDb.doc(`tryOnSessions/${sessionId}`).set({
      userId: UID,
      status: "generating",
      productId: PRODUCT_ID,
      colorKey: COLOR,
      size: null,
      garmentStoragePath: "x",
      garmentCategory: "top",
      failureReason: null,
      resultPath: null,
      provider: "gemini",
      providerModel: "gemini-2.5-flash-image",
      idempotencyKey: key,
      updatedAt: Timestamp.fromMillis(NOW),
    });
    await expectAppError(call(body({ idempotencyKey: key })), "SESSION_IN_PROGRESS");
  });
});

describe("generateTryOn - rate limiting (D9)", () => {
  it("allows exactly the hourly cap (5), then refuses the 6th with RATE_LIMITED - no provider call on the refusal", async () => {
    await seedVtoProduct(PRODUCT_ID, COLOR);
    for (let i = 0; i < 5; i++) {
      const key = `hour-key-${i}`;
      await seedPhotoForKey(UID, key);
      await call(body({ idempotencyKey: key }), { now: NOW });
    }
    const fake = makeFakeVtoProvider();
    await expectAppError(
      call(body({ idempotencyKey: "hour-key-6" }), { provider: fake, now: NOW }),
      "RATE_LIMITED",
    );
    expect(fake.calls).toHaveLength(0);
    // No session was created for the refused attempt.
    expect(await readTryOnSession(tryOnSessionIdFor(UID, "hour-key-6"))).toBeUndefined();
  });

  it("the hourly cap resets after an hour has elapsed", async () => {
    await seedVtoProduct(PRODUCT_ID, COLOR);
    for (let i = 0; i < 5; i++) {
      const key = `hour-reset-key-${i}`;
      await seedPhotoForKey(UID, key);
      await call(body({ idempotencyKey: key }), { now: NOW });
    }
    const nextHourKey = "hour-reset-key-next";
    await seedPhotoForKey(UID, nextHourKey);
    const { result } = await call(body({ idempotencyKey: nextHourKey }), { now: NOW + 61 * 60 * 1000 });
    expect(result.status).toBe("succeeded");
  });

  it("the daily cap (10) refuses even across multiple hourly windows", async () => {
    await seedVtoProduct(PRODUCT_ID, COLOR);
    let now = NOW;
    for (let i = 0; i < 10; i++) {
      const key = `day-key-${i}`;
      await seedPhotoForKey(UID, key);
      await call(body({ idempotencyKey: key }), { now });
      now += 61 * 60 * 1000; // roll past the hourly window every time
    }
    const fake = makeFakeVtoProvider();
    await expectAppError(
      call(body({ idempotencyKey: "day-key-11" }), { provider: fake, now }),
      "RATE_LIMITED",
    );
    expect(fake.calls).toHaveLength(0);
  });

  it("does not let one user's usage affect another user's quota", async () => {
    await seedVtoProduct(PRODUCT_ID, COLOR);
    for (let i = 0; i < 5; i++) {
      const key = `alice-hour-key-${i}`;
      await seedPhotoForKey(UID, key);
      await call(body({ idempotencyKey: key }), { now: NOW });
    }
    const bobKey = "bob-key-1";
    await seedPhotoForKey(OTHER_UID, bobKey);
    const { result } = await call(body({ idempotencyKey: bobKey }), { uid: OTHER_UID, now: NOW });
    expect(result.status).toBe("succeeded");
  });

  it("the global daily cap (50) refuses even a fresh user with room left on their own cap", async () => {
    await seedVtoProduct(PRODUCT_ID, COLOR);
    await testDb.doc("tryOnQuota/_global").set({
      dayWindowStart: Timestamp.fromMillis(NOW),
      dayCount: 50,
      updatedAt: Timestamp.fromMillis(NOW),
    });

    const key = "global-capped-key";
    await seedPhotoForKey(UID, key);
    const fake = makeFakeVtoProvider();
    await expectAppError(
      call(body({ idempotencyKey: key }), { provider: fake, now: NOW }),
      "GLOBAL_LIMIT_REACHED",
    );
    expect(fake.calls).toHaveLength(0);
    // The refused caller's own per-user quota is untouched.
    expect(await readTryOnUserQuota(UID)).toBeUndefined();
  });
});

// 2026-09-11 hardening pass ---------------------------------------------

describe("generateTryOn - hardening: person upload deleted on EVERY pre-generation refusal (issue #1)", () => {
  it("an ineligible product still deletes the already-uploaded person photo", async () => {
    await seedVtoProduct(PRODUCT_ID, COLOR, { vtoDisabled: true });
    const key = "cleanup-ineligible-key";
    const uploadPath = await seedPhotoForKey(UID, key);
    await expectAppError(call(body({ idempotencyKey: key })), "PRODUCT_NOT_ELIGIBLE");
    expect(await storageObjectExists(uploadPath)).toBe(false);
  });

  it("an unavailable variant still deletes the already-uploaded person photo", async () => {
    await seedVtoProduct(PRODUCT_ID, COLOR);
    const key = "cleanup-variant-key";
    const uploadPath = await seedPhotoForKey(UID, key);
    await expectAppError(call(body({ idempotencyKey: key, colorKey: "purple" })), "VARIANT_UNAVAILABLE");
    expect(await storageObjectExists(uploadPath)).toBe(false);
  });

  it("a rate-limited request still deletes the already-uploaded person photo", async () => {
    await seedVtoProduct(PRODUCT_ID, COLOR);
    for (let i = 0; i < 5; i++) {
      const key = `cleanup-hour-key-${i}`;
      await seedPhotoForKey(UID, key);
      await call(body({ idempotencyKey: key }), { now: NOW });
    }
    const sixthUpload = await seedPhotoForKey(UID, "cleanup-hour-key-6");
    await expectAppError(call(body({ idempotencyKey: "cleanup-hour-key-6" }), { now: NOW }), "RATE_LIMITED");
    expect(await storageObjectExists(sixthUpload)).toBe(false);
  });

  it("the global-limit refusal still deletes the already-uploaded person photo", async () => {
    await seedVtoProduct(PRODUCT_ID, COLOR);
    await testDb.doc("tryOnQuota/_global").set({
      dayWindowStart: Timestamp.fromMillis(NOW),
      dayCount: 50,
      updatedAt: Timestamp.fromMillis(NOW),
    });
    const key = "cleanup-global-key";
    const uploadPath = await seedPhotoForKey(UID, key);
    await expectAppError(call(body({ idempotencyKey: key }), { now: NOW }), "GLOBAL_LIMIT_REACHED");
    expect(await storageObjectExists(uploadPath)).toBe(false);
  });

  it("a foreign-session (FORBIDDEN) refusal still deletes the caller's own already-uploaded photo", async () => {
    await seedVtoProduct(PRODUCT_ID, COLOR);
    const key = "cleanup-forbidden-key";
    const sessionId = tryOnSessionIdFor(UID, key);
    await testDb.doc(`tryOnSessions/${sessionId}`).set({
      userId: OTHER_UID,
      status: "pending",
      productId: PRODUCT_ID,
      colorKey: COLOR,
      size: null,
      garmentStoragePath: "x",
      garmentCategory: "top",
      failureReason: null,
      resultPath: null,
      provider: "gemini",
      providerModel: "gemini-2.5-flash-image",
      idempotencyKey: key,
    });
    const uploadPath = await seedPhotoForKey(UID, key);
    await expectAppError(call(body({ idempotencyKey: key })), "FORBIDDEN");
    expect(await storageObjectExists(uploadPath)).toBe(false);
  });

  it("a SESSION_IN_PROGRESS refusal still deletes the caller's own already-uploaded photo", async () => {
    await seedVtoProduct(PRODUCT_ID, COLOR);
    const key = "cleanup-in-progress-key";
    const sessionId = tryOnSessionIdFor(UID, key);
    await testDb.doc(`tryOnSessions/${sessionId}`).set({
      userId: UID,
      status: "generating",
      productId: PRODUCT_ID,
      colorKey: COLOR,
      size: null,
      garmentStoragePath: "x",
      garmentCategory: "top",
      failureReason: null,
      resultPath: null,
      provider: "gemini",
      providerModel: "gemini-2.5-flash-image",
      idempotencyKey: key,
      updatedAt: Timestamp.fromMillis(NOW),
    });
    const uploadPath = await seedPhotoForKey(UID, key);
    await expectAppError(call(body({ idempotencyKey: key })), "SESSION_IN_PROGRESS");
    expect(await storageObjectExists(uploadPath)).toBe(false);
  });

  it("a SESSION_ATTEMPT_CLOSED refusal still deletes a freshly re-uploaded photo for the closed key", async () => {
    await seedVtoProduct(PRODUCT_ID, COLOR);
    const key = "cleanup-attempt-closed-key";
    await seedPhotoForKey(UID, key);
    const fake = makeFakeVtoProvider({ failWith: new VtoProviderError("network", "503") });
    await expectAppError(call(body({ idempotencyKey: key }), { provider: fake }), "PROVIDER_UNAVAILABLE");

    // The customer retries with the SAME (now-closed) key and, for whatever
    // reason, re-uploads a photo first - it must still be cleaned up even
    // though the attempt itself is refused.
    const reuploadPath = await seedPhotoForKey(UID, key);
    await expectAppError(call(body({ idempotencyKey: key })), "SESSION_ATTEMPT_CLOSED");
    expect(await storageObjectExists(reuploadPath)).toBe(false);
  });
});

describe("generateTryOn - hardening: unexpected-failure recovery, never a silently orphaned result (issue #2)", () => {
  it("rolls back the just-written result object if the final Firestore 'succeeded' update unexpectedly fails, and marks the session failed", async () => {
    await seedVtoProduct(PRODUCT_ID, COLOR);
    const key = "rollback-key";
    await seedPhotoForKey(UID, key);
    const sessionId = tryOnSessionIdFor(UID, key);

    // A provider whose successful response arrives just as the session
    // document is unexpectedly deleted out from under the request (a
    // concurrent admin/ops action, or a user-deletion race) - the final
    // `.update()` to `succeeded` will genuinely throw NOT_FOUND against the
    // real Firestore emulator.
    const deletingProvider = {
      name: "fake-deleting",
      async generate() {
        await testDb.doc(`tryOnSessions/${sessionId}`).delete();
        return { imageBytes: PNG_RESULT_BYTES, contentType: "image/png" };
      },
    };

    await expectAppError(
      generateTryOnHandler({
        authUid: UID,
        data: body({ idempotencyKey: key }),
        provider: deletingProvider,
        now: () => NOW,
      }),
      "INTERNAL",
    );

    // The result object must not survive under EITHER extension - it was
    // rolled back since there is no session record confirming it.
    expect(await storageObjectExists(`users/${UID}/tryOnResults/${sessionId}.jpg`)).toBe(false);
    expect(await storageObjectExists(`users/${UID}/tryOnResults/${sessionId}.png`)).toBe(false);
  });

  it("still deletes the person upload even when an unexpected failure occurs", async () => {
    await seedVtoProduct(PRODUCT_ID, COLOR);
    const key = "rollback-cleanup-key";
    const uploadPath = await seedPhotoForKey(UID, key);
    const sessionId = tryOnSessionIdFor(UID, key);

    const deletingProvider = {
      name: "fake-deleting",
      async generate() {
        await testDb.doc(`tryOnSessions/${sessionId}`).delete();
        return { imageBytes: PNG_RESULT_BYTES, contentType: "image/png" };
      },
    };

    await expectAppError(
      generateTryOnHandler({
        authUid: UID,
        data: body({ idempotencyKey: key }),
        provider: deletingProvider,
        now: () => NOW,
      }),
      "INTERNAL",
    );
    expect(await storageObjectExists(uploadPath)).toBe(false);
  });
});

describe("generateTryOn - hardening: cached-success expiry is the REAL stored value (issue #4)", () => {
  it("a retry after success returns the session's actual stored expiresAt, not the retry call's current time", async () => {
    await seedVtoProduct(PRODUCT_ID, COLOR);
    const key = "expiry-cache-key";
    await seedPhotoForKey(UID, key);

    const first = await call(body({ idempotencyKey: key }), { now: NOW });
    expect(first.result.expiresAt).toBeGreaterThan(NOW);

    const muchLater = NOW + 5 * 60 * 60 * 1000; // 5 hours later, still under the 24h TTL
    const second = await call(body({ idempotencyKey: key }), { now: muchLater });

    expect(second.result.expiresAt).toBe(first.result.expiresAt);
    expect(second.result.expiresAt).not.toBe(muchLater);
  });

  it("a retry after the stored expiresAt has passed but BEFORE the sweep runs is refused, never hands back an expired result", async () => {
    await seedVtoProduct(PRODUCT_ID, COLOR);
    const key = "expiry-passed-key";
    await seedPhotoForKey(UID, key);

    const first = await call(body({ idempotencyKey: key }), { now: NOW });
    expect(first.result.status).toBe("succeeded");

    // The session doc is still `succeeded` in Firestore (no sweep has run -
    // `cleanupExpiredTryOnMedia` runs every 30 min and this test never calls
    // it) - only the STORED expiresAt has genuinely passed.
    const pastExpiry = first.result.expiresAt + 1;
    const fake = makeFakeVtoProvider();
    await expectAppError(
      call(body({ idempotencyKey: key }), { provider: fake, now: pastExpiry }),
      "SESSION_ATTEMPT_CLOSED",
    );
    // The refusal never falls through to a real (billable) generation either.
    expect(fake.calls).toHaveLength(0);

    // The result object itself is untouched by this refusal (the sweep, not
    // this call, is what eventually deletes it) - only the cached-replay
    // path fails closed.
    expect(await storageObjectExists(first.result.resultPath)).toBe(true);
  });

  it("a retry exactly one millisecond before the stored expiresAt still returns the cached result", async () => {
    await seedVtoProduct(PRODUCT_ID, COLOR);
    const key = "expiry-boundary-key";
    await seedPhotoForKey(UID, key);

    const first = await call(body({ idempotencyKey: key }), { now: NOW });
    const fake = makeFakeVtoProvider();
    const second = await call(body({ idempotencyKey: key }), {
      provider: fake,
      now: first.result.expiresAt - 1,
    });
    expect(second.result.status).toBe("succeeded");
    expect(second.result.resultPath).toBe(first.result.resultPath);
    expect(fake.calls).toHaveLength(0); // cached - no new provider call
  });
});

describe("generateTryOn - hardening: file integrity re-verification (issue #5)", () => {
  it("rejects a person upload whose declared content-type does not match its actual byte signature (spoofed upload)", async () => {
    await seedVtoProduct(PRODUCT_ID, COLOR);
    const key = "spoofed-photo-key";
    const sessionId = tryOnSessionIdFor(UID, key);
    // storage.rules only gate the DECLARED metadata contentType - upload
    // non-image bytes labelled as image/jpeg to prove the server-side
    // signature re-check catches what the rules alone cannot.
    await uploadTestObject(
      `users/${UID}/tryOnUploads/${sessionId}.jpg`,
      Buffer.from("this is not actually a jpeg"),
      "image/jpeg",
    );
    const fake = makeFakeVtoProvider();
    await expectAppError(call(body({ idempotencyKey: key }), { provider: fake }), "PHOTO_INVALID");
    expect(fake.calls).toHaveLength(0); // never reached the (billable) provider call
  });

  it("rejects when the actual garment Storage bytes don't match the Firestore-recorded sha256 (integrity mismatch) and never calls the provider", async () => {
    // A dedicated product/colour so no other test's upload interferes.
    const productId = "integrity-mismatch-product";
    const colorKey = "teal";
    await seedVtoProduct(productId, colorKey, {}, { sha256: "b".repeat(64) }); // wrong hash vs the real uploaded bytes
    const key = "garment-integrity-key";
    await seedPhotoForKey(UID, key);
    const fake = makeFakeVtoProvider();
    await expectAppError(
      call(body({ productId, colorKey, idempotencyKey: key }), { provider: fake }),
      "GARMENT_UNAVAILABLE",
    );
    expect(fake.calls).toHaveLength(0);
    const session = await readTryOnSession(tryOnSessionIdFor(UID, key));
    expect(session?.failureReason).toBe("garment_integrity_mismatch");
  });

  it("rejects when the Storage object's own contentType metadata disagrees with the Firestore-recorded contentType, even though bytes/hash/size are correct", async () => {
    const productId = "integrity-metadata-mismatch-product";
    const colorKey = "olive";
    await seedVtoProduct(productId, colorKey);
    const garmentPath = `products/${productId}/vto/garment-${colorKey}-v1.jpg`;
    const realBytes = await readStorageObjectBytes(garmentPath);
    // Re-upload the IDENTICAL bytes (so sha256/byteSize/signature all still
    // agree with the Firestore record's declared image/jpeg) but under a
    // DIFFERENT Storage contentType metadata label - simulates the object's
    // own metadata drifting out of sync with Firestore (a bug/migration/
    // console edit), which the sha256/signature checks alone cannot catch.
    await uploadTestObject(garmentPath, realBytes as Buffer, "image/png");

    const key = "garment-metadata-mismatch-key";
    await seedPhotoForKey(UID, key);
    const fake = makeFakeVtoProvider();
    await expectAppError(
      call(body({ productId, colorKey, idempotencyKey: key }), { provider: fake }),
      "GARMENT_UNAVAILABLE",
    );
    expect(fake.calls).toHaveLength(0); // never reached the (billable) provider call
    const session = await readTryOnSession(tryOnSessionIdFor(UID, key));
    expect(session?.failureReason).toBe("garment_integrity_mismatch");
  });

  it("rejects when the actual garment Storage byte size doesn't match the Firestore-recorded byteSize", async () => {
    const productId = "integrity-size-product";
    const colorKey = "maroon";
    await seedVtoProduct(productId, colorKey, {}, { byteSize: 999_999 }); // wrong size vs the real uploaded bytes
    const key = "garment-size-key";
    await seedPhotoForKey(UID, key);
    const fake = makeFakeVtoProvider();
    await expectAppError(
      call(body({ productId, colorKey, idempotencyKey: key }), { provider: fake }),
      "GARMENT_UNAVAILABLE",
    );
    expect(fake.calls).toHaveLength(0);
  });

  it("saves a PNG provider result under a .png path, never a misleading .jpg name", async () => {
    await seedVtoProduct(PRODUCT_ID, COLOR);
    const key = "png-extension-key";
    await seedPhotoForKey(UID, key);
    const fake = makeFakeVtoProvider({ resultBytes: PNG_RESULT_BYTES, resultContentType: "image/png" });
    const { result } = await call(body({ idempotencyKey: key }), { provider: fake });
    expect(result.resultPath).toMatch(/\.png$/);
    expect(await storageObjectExists(result.resultPath)).toBe(true);
  });

  it("saves a JPEG provider result under a .jpg path", async () => {
    await seedVtoProduct(PRODUCT_ID, COLOR);
    const key = "jpg-extension-key";
    await seedPhotoForKey(UID, key);
    const jpegResult = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3, 4]);
    const fake = makeFakeVtoProvider({ resultBytes: jpegResult, resultContentType: "image/jpeg" });
    const { result } = await call(body({ idempotencyKey: key }), { provider: fake });
    expect(result.resultPath).toMatch(/\.jpg$/);
  });

  it("rejects a provider response whose declared contentType doesn't match its actual bytes, and never writes a result object", async () => {
    await seedVtoProduct(PRODUCT_ID, COLOR);
    const key = "provider-signature-mismatch-key";
    await seedPhotoForKey(UID, key);
    const sessionId = tryOnSessionIdFor(UID, key);
    // Declares image/png but the bytes are garbage - a misbehaving or
    // compromised provider response.
    const fake = makeFakeVtoProvider({ resultBytes: Buffer.from("definitely not a png"), resultContentType: "image/png" });
    await expectAppError(call(body({ idempotencyKey: key }), { provider: fake }), "PROVIDER_UNAVAILABLE");
    expect(await storageObjectExists(`users/${UID}/tryOnResults/${sessionId}.jpg`)).toBe(false);
    expect(await storageObjectExists(`users/${UID}/tryOnResults/${sessionId}.png`)).toBe(false);
    const session = await readTryOnSession(sessionId);
    expect(session?.status).toBe("failed");
    expect(session?.failureReason).toBe("invalid_result");
  });
});
