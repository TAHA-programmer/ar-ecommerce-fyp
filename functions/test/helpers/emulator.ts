/**
 * Shared setup for the `createPaymentIntent` emulator integration tests.
 *
 * These run the REAL handler against the REAL Firestore emulator (Admin SDK),
 * so transactions, contention retries and atomicity behave exactly as in
 * production. The Stripe boundary is always a MOCK - no live or sandbox
 * Stripe call is ever made from an automated test.
 */
process.env.GCLOUD_PROJECT ||= "demo-twin-ar-fns";
process.env.GOOGLE_CLOUD_PROJECT ||= process.env.GCLOUD_PROJECT;
process.env.FIRESTORE_EMULATOR_HOST ||= "127.0.0.1:8080";
// Phase 9.3 Stage 4 - the Virtual Try-On emulator tests also need Storage
// (person-photo upload, garment asset, generated result). Harmless for every
// pre-existing Firestore-only test in this directory.
process.env.FIREBASE_STORAGE_EMULATOR_HOST ||= "127.0.0.1:9199";

import { createHash } from "node:crypto";

import { getApps, initializeApp } from "firebase-admin/app";
import { FieldValue, getFirestore, Timestamp } from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";
import Stripe from "stripe";

import { createPaymentIntentHandler } from "../../src/createPaymentIntent";
import type { StripePaymentApi, StripePaymentIntentLike } from "../../src/lib/stripe";

const PROJECT_ID = process.env.GCLOUD_PROJECT as string;

if (getApps().length === 0) {
  initializeApp({ projectId: PROJECT_ID, storageBucket: `${PROJECT_ID}.appspot.com` });
}

export const testDb = getFirestore();
export const testBucket = getStorage().bucket();

export async function clearFirestore(): Promise<void> {
  const host = process.env.FIRESTORE_EMULATOR_HOST as string;
  const res = await fetch(
    `http://${host}/emulator/v1/projects/${PROJECT_ID}/databases/(default)/documents`,
    { method: "DELETE" },
  );
  if (!res.ok) {
    throw new Error(`clearFirestore failed: ${res.status} ${await res.text()}`);
  }
}

export function productData(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    sku: "SKU-TEST",
    title: "Test Chair",
    description: "",
    categoryId: "furniture",
    categoryKind: "furniture",
    subcategory: "",
    priceAmount: 12000,
    originalPriceAmount: null,
    stockQuantity: 5,
    isActive: true,
    showInCatalog: true,
    publicationStatus: "published",
    mainImage: { path: "products/test/main.jpg", source: "network", altText: "" },
    galleryMedia: [],
    experienceType: "none",
    vtoModelType: null,
    availableColors: [],
    availableSizes: [],
    defaultColor: null,
    defaultSize: null,
    specifications: [],
    deliveryEstimate: "",
    warranty: null,
    recommendationRank: 0,
    popularityScore: 0,
    addedDate: Timestamp.fromMillis(0),
    rating: 0,
    reviewCount: 0,
    arModelAssetPath: null,
    arScale: null,
    vtoGarmentAssetPath: null,
    ...overrides,
  };
}

export async function seedProduct(
  id: string,
  overrides: Record<string, unknown> = {},
): Promise<void> {
  await testDb.doc(`products/${id}`).set(productData(overrides));
}

export async function seedAddress(
  uid: string,
  addressId: string,
  overrides: Record<string, unknown> = {},
): Promise<void> {
  await testDb.doc(`users/${uid}/addresses/${addressId}`).set({
    label: "Home",
    fullName: "Alice Khan",
    phoneNumber: "03001234567",
    addressLine1: "1 Test Road",
    addressLine2: null,
    city: "Karachi",
    provinceOrState: "Sindh",
    postalCode: "74000",
    createdAt: FieldValue.serverTimestamp(),
    ...overrides,
  });
}

export async function seedDefaultPointer(uid: string, addressId: string | null): Promise<void> {
  await testDb.doc(`users/${uid}/addressDefault/pointer`).set({
    defaultAddressId: addressId,
    updatedAt: FieldValue.serverTimestamp(),
  });
}

export async function readProductStock(id: string): Promise<number> {
  const snap = await testDb.doc(`products/${id}`).get();
  return (snap.data()?.stockQuantity as number | undefined) ?? -999;
}

export async function readProduct(id: string): Promise<Record<string, unknown> | undefined> {
  return (await testDb.doc(`products/${id}`).get()).data();
}

export async function readSession(sessionId: string): Promise<Record<string, unknown> | undefined> {
  return (await testDb.doc(`checkoutSessions/${sessionId}`).get()).data();
}

export async function readOrder(id: string): Promise<Record<string, unknown> | undefined> {
  return (await testDb.doc(`orders/${id}`).get()).data();
}

export async function readPayment(id: string): Promise<Record<string, unknown> | undefined> {
  return (await testDb.doc(`payments/${id}`).get()).data();
}

export async function readStripeEvent(id: string): Promise<Record<string, unknown> | undefined> {
  return (await testDb.doc(`stripeEvents/${id}`).get()).data();
}

// ---- Stripe webhook signing (mocked - never a real secret) --------------

/** A syntactically-valid but entirely fake webhook signing secret for tests. */
export const TEST_WEBHOOK_SECRET = "whsec_test_0000000000000000000000000000000000000000";

const stripeForSigning = new Stripe("sk_test_placeholder_used_only_to_sign_test_events");

export interface StripeEventObject {
  id: string;
  object: "event";
  type: string;
  livemode: boolean;
  data: { object: Record<string, unknown> };
}

export function makePaymentIntentEvent(params: {
  eventId: string;
  type: string;
  paymentIntentId: string;
  amountMinor: number;
  currency?: string;
  checkoutSessionId: string | null;
  firebaseUserId: string | null;
  livemode?: boolean;
}): StripeEventObject {
  const metadata: Record<string, string> = {};
  if (params.checkoutSessionId !== null) metadata.checkoutSessionId = params.checkoutSessionId;
  if (params.firebaseUserId !== null) metadata.firebaseUserId = params.firebaseUserId;
  metadata.appPhase = "twin_ar_8_13_2";
  return {
    id: params.eventId,
    object: "event",
    type: params.type,
    livemode: params.livemode ?? false,
    data: {
      object: {
        id: params.paymentIntentId,
        object: "payment_intent",
        amount: params.amountMinor,
        currency: params.currency ?? "pkr",
        status: params.type === "payment_intent.succeeded" ? "succeeded" : "requires_payment_method",
        // A real PI object carries client_secret - included here so the
        // "never log secrets" behaviour is exercised against realistic input.
        client_secret: `${params.paymentIntentId}_secret_TEST_SHOULD_NOT_BE_LOGGED`,
        metadata,
      },
    },
  };
}

/** Serialise + sign an event exactly as Stripe would, using TEST_WEBHOOK_SECRET. */
export function signStripeEvent(event: StripeEventObject): {
  rawBody: string;
  signature: string;
} {
  const rawBody = JSON.stringify(event);
  const signature = stripeForSigning.webhooks.generateTestHeaderString({
    payload: rawBody,
    secret: TEST_WEBHOOK_SECRET,
  });
  return { rawBody, signature };
}

interface FakePi {
  id: string;
  status: string;
  amount: number;
  currency: string;
  metadata: Record<string, string>;
}

export interface FakeStripeOptions {
  failEveryCreate?: unknown;
  failNextCreateOnce?: unknown;
  /** Status a newly-created PI starts in. Default `requires_payment_method`. */
  initialStatus?: string;
  /** Force retrieve()/cancel() views to report this status for every PI. */
  forceStatus?: string;
  /** cancel() throws this instead of cancelling. */
  failCancelWith?: unknown;
  /** cancel() leaves the PI in this status instead of `canceled`. */
  cancelResultStatus?: string;
  /** createRefund() throws this. */
  failRefundWith?: unknown;
  /** Awaited at the start of cancel(id) - lets a test inject a race. */
  onBeforeCancel?: (id: string) => void | Promise<void>;
  /** Awaited at the start of retrieve(id). */
  onBeforeRetrieve?: (id: string) => void | Promise<void>;
}

export interface FakeStripe {
  api: StripePaymentApi;
  calls: {
    create: { params: unknown; options?: { idempotencyKey?: string } }[];
    retrieve: string[];
    cancel: { id: string; options?: { idempotencyKey?: string } }[];
    refund: { paymentIntentId: string; options?: { idempotencyKey?: string } }[];
  };
  /** Directly set a PI's stored status (test helper). */
  setStatus(id: string, status: string): void;
  getStatus(id: string): string | undefined;
}

function stripeError(message: string, type: string, code?: string): Error {
  const e = new Error(message) as Error & { type: string; code?: string };
  e.type = type;
  if (code) e.code = code;
  return e;
}

/**
 * A stateful mock Stripe boundary. Models idempotency for create + refund,
 * tracks PI status across retrieve/cancel, and returns the full
 * `StripePaymentIntentLike` shape (amount/currency/metadata).
 */
export function makeFakeStripe(opts: FakeStripeOptions = {}): FakeStripe {
  const calls: FakeStripe["calls"] = { create: [], retrieve: [], cancel: [], refund: [] };
  const byKey = new Map<string, FakePi>();
  const byId = new Map<string, FakePi>();
  const refundsByKey = new Map<string, { id: string; status: string }>();
  let failCreateOnce = opts.failNextCreateOnce;

  const view = (pi: FakePi): StripePaymentIntentLike => ({
    id: pi.id,
    client_secret: `${pi.id}_secret_test`,
    status: opts.forceStatus ?? pi.status,
    amount: pi.amount,
    currency: pi.currency,
    metadata: { ...pi.metadata },
  });

  const api: StripePaymentApi = {
    async create(params, options) {
      calls.create.push({ params, options });
      if (opts.failEveryCreate !== undefined) throw opts.failEveryCreate;
      if (failCreateOnce !== undefined) {
        const err = failCreateOnce;
        failCreateOnce = undefined;
        throw err;
      }
      const key = options?.idempotencyKey ?? `nokey_${calls.create.length}`;
      const existing = byKey.get(key);
      if (existing) return view(existing);
      const pi: FakePi = {
        id: `pi_${key}`,
        status: opts.initialStatus ?? "requires_payment_method",
        amount: params.amount,
        currency: params.currency,
        metadata: { ...(params.metadata ?? {}) },
      };
      byKey.set(key, pi);
      byId.set(pi.id, pi);
      return view(pi);
    },
    async retrieve(id) {
      calls.retrieve.push(id);
      await opts.onBeforeRetrieve?.(id);
      const pi = byId.get(id);
      if (!pi) throw stripeError("No such payment_intent", "StripeInvalidRequestError", "resource_missing");
      return view(pi);
    },
    async cancel(id, options) {
      calls.cancel.push({ id, options });
      await opts.onBeforeCancel?.(id);
      if (opts.failCancelWith !== undefined) throw opts.failCancelWith;
      const pi = byId.get(id);
      if (!pi) throw stripeError("No such payment_intent", "StripeInvalidRequestError", "resource_missing");
      if (pi.status === "succeeded") {
        throw stripeError("already succeeded", "StripeInvalidRequestError", "payment_intent_unexpected_state");
      }
      pi.status = opts.cancelResultStatus ?? "canceled";
      return view(pi);
    },
    async createRefund({ paymentIntentId }, options) {
      calls.refund.push({ paymentIntentId, options });
      if (opts.failRefundWith !== undefined) throw opts.failRefundWith;
      const key = options?.idempotencyKey ?? `refund_${calls.refund.length}`;
      const existing = refundsByKey.get(key);
      if (existing) return existing;
      const r = { id: `re_${key}`, status: "succeeded" };
      refundsByKey.set(key, r);
      return r;
    },
  };

  return {
    api,
    calls,
    setStatus(id, status) {
      const pi = byId.get(id);
      if (pi) pi.status = status;
    },
    getStatus(id) {
      return byId.get(id)?.status;
    },
  };
}

/** Run a real reservation through `createPaymentIntent`, sharing a fake Stripe. */
export async function reserveViaHandler(
  stripe: FakeStripe,
  opts: {
    uid: string;
    addressId: string;
    items?: { productId: string; quantity: number; selectedColor?: string | null; selectedSize?: string | null }[];
    idempotencyKey?: string;
    nowMs?: number;
  },
): Promise<{ sessionId: string; piId: string; amountMinor: number; totals: Record<string, number> }> {
  const result = await createPaymentIntentHandler({
    authUid: opts.uid,
    data: {
      addressId: opts.addressId,
      idempotencyKey: opts.idempotencyKey ?? `idem-${Math.random().toString(36).slice(2)}-key`,
      items: opts.items ?? [{ productId: "p1", quantity: 1 }],
    },
    stripe: stripe.api,
    now: () => opts.nowMs ?? 1_700_000_000_000,
  });
  const session = await readSession(result.checkoutSessionId);
  return {
    sessionId: result.checkoutSessionId,
    piId: session!.stripePaymentIntentId as string,
    amountMinor: result.amount,
    totals: result.totals as unknown as Record<string, number>,
  };
}

// ---- Storage helpers (Phase 9.3 Stage 4 - Virtual Try-On) ----------------

export async function uploadTestObject(
  path: string,
  bytes: Buffer,
  contentType: string,
): Promise<void> {
  await testBucket.file(path).save(bytes, { contentType, resumable: false });
}

export async function storageObjectExists(path: string): Promise<boolean> {
  const [exists] = await testBucket.file(path).exists();
  return exists;
}

export async function readStorageObjectBytes(path: string): Promise<Buffer | null> {
  const file = testBucket.file(path);
  const [exists] = await file.exists();
  if (!exists) return null;
  const [bytes] = await file.download();
  return bytes;
}

// ---- Virtual Try-On helpers (Phase 9.3 Stage 4) ---------------------------

// A real, valid JPEG signature (FFD8FF...) - long enough to also satisfy the
// hardening pass's byte-signature re-verification (`imageSniff.ts`), not
// just the storage.rules content-type gate.
const JPEG_BYTES = Buffer.from([
  0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46, 0x49, 0x46, 0x00, 0x01, 1, 2, 3, 4, 5, 6, 7, 8,
]);
const JPEG_SHA256 = createHash("sha256").update(JPEG_BYTES).digest("hex");
// A real, valid PNG signature - the default fake-provider "generated" result,
// so the generation-time provider-output signature re-verification
// (`imageSniff.ts`) passes for a normal, honest success-path test.
export const PNG_RESULT_BYTES = Buffer.from([
  0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 1, 2, 3, 4,
]);

/** A well-formed garment-asset map entry, matching `ProductVtoMetadata`'s
 *  Firestore shape and `resolveEligibleGarment`'s ownership-path check. The
 *  default `sha256`/`byteSize` are the REAL hash/length of the bytes
 *  `seedVtoProduct` actually uploads, so the generation-time integrity
 *  re-verification (2026-09-11 hardening) passes for a normal, honest test
 *  fixture - pass explicit overrides to deliberately test a mismatch. */
export function vtoGarmentAsset(
  productId: string,
  slot: string,
  overrides: Record<string, unknown> = {},
): Record<string, unknown> {
  return {
    storagePath: `products/${productId}/vto/garment-${slot}-v1.jpg`,
    sha256: JPEG_SHA256,
    contentType: "image/jpeg",
    byteSize: JPEG_BYTES.length,
    width: 900,
    height: 1200,
    version: 1,
    ...overrides,
  };
}

/** `productData()` overrides for a fully VTO-eligible product with one
 *  garment asset under `colorKey`. Also uploads the garment bytes to Storage
 *  (bypassing storage.rules, same as every other Admin-SDK test seed).
 *  `garmentOverrides` customizes the garment-asset map entry itself (e.g. a
 *  malformed sha256 or a foreign storagePath); `productOverrides` customizes
 *  the rest of the product document (e.g. `vtoDisabled: true`). */
export async function seedVtoProduct(
  productId: string,
  colorKey: string,
  productOverrides: Record<string, unknown> = {},
  garmentOverrides: Record<string, unknown> = {},
): Promise<void> {
  const garment = vtoGarmentAsset(productId, colorKey, garmentOverrides);
  const { skipGarmentUpload, ...docOverrides } = productOverrides as { skipGarmentUpload?: boolean } & Record<
    string,
    unknown
  >;
  await seedProduct(productId, {
    experienceType: "virtualTryOn",
    vtoModelType: "female",
    availableColors: [colorKey],
    availableSizes: ["S", "M", "L"],
    defaultColor: colorKey,
    defaultSize: "M",
    vtoGarmentCategory: "top",
    vtoContract: "twin-ar/vto-contract-9.3",
    vtoGarments: { [colorKey]: garment },
    vtoDisabled: false,
    ...docOverrides,
  });
  if (!skipGarmentUpload) {
    await uploadTestObject(garment.storagePath as string, JPEG_BYTES, garment.contentType as string);
  }
}

export async function seedPersonPhoto(uid: string, sessionId: string): Promise<string> {
  const path = `users/${uid}/tryOnUploads/${sessionId}.jpg`;
  await uploadTestObject(path, JPEG_BYTES, "image/jpeg");
  return path;
}

export async function readTryOnSession(sessionId: string): Promise<Record<string, unknown> | undefined> {
  return (await testDb.doc(`tryOnSessions/${sessionId}`).get()).data();
}

export async function readTryOnUserQuota(uid: string): Promise<Record<string, unknown> | undefined> {
  return (await testDb.doc(`tryOnQuota/${uid}`).get()).data();
}

export async function readTryOnGlobalQuota(): Promise<Record<string, unknown> | undefined> {
  return (await testDb.doc("tryOnQuota/_global").get()).data();
}

export interface FakeVtoProviderOptions {
  resultBytes?: Buffer;
  resultContentType?: string;
  /** Thrown by `generate()` on every call, e.g. a `VtoProviderError`. */
  failWith?: unknown;
}

/** A stateful fake `VtoProvider` - tracks every call, never touches the network. */
export function makeFakeVtoProvider(opts: FakeVtoProviderOptions = {}) {
  const calls: unknown[] = [];
  return {
    calls,
    provider: {
      name: "fake",
      async generate(input: unknown) {
        calls.push(input);
        if (opts.failWith !== undefined) throw opts.failWith;
        return {
          imageBytes: opts.resultBytes ?? PNG_RESULT_BYTES,
          contentType: opts.resultContentType ?? "image/png",
        };
      },
    },
  };
}

export { FieldValue, Timestamp };
