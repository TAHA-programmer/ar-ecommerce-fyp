import { createHash } from "node:crypto";

import { FieldValue, Timestamp } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";

import {
  FUNCTIONS_REGION,
  VTO_PERSON_PHOTO_MAX_BYTES,
  VTO_PROVIDER_MODEL,
  VTO_PROVIDER_NAME,
  VTO_RESULT_MAX_BYTES,
  VTO_RESULT_TTL_MS,
  geminiApiKey,
} from "./config";
import { resolveEligibleGarment, type ResolvedGarment } from "./lib/tryOn/eligibility";
import {
  errGarmentUnavailable,
  errInternal,
  errPhotoInvalid,
  errPhotoMissing,
  errProductUnavailable,
  errProviderRefused,
  errProviderUnavailable,
  errTimeout,
  errUnauthenticated,
  logUnexpected,
} from "./lib/tryOn/errors";
import { productDoc, tryOnSessionDoc } from "./lib/firestore";
import { bytesMatchDeclaredType, extensionForContentType, sniffImageContentType } from "./lib/tryOn/imageSniff";
import { geminiProvider, VtoProviderError, type VtoGenerateResult, type VtoProvider } from "./lib/tryOn/provider";
import { reserveTryOnSessionOrClassify } from "./lib/tryOn/reservation";
import { deleteObjectBestEffort, readObjectBytes, writeObjectBytes } from "./lib/tryOn/storage";
import { tryOnResultPath, tryOnSessionIdFor, tryOnUploadPath } from "./lib/tryOn/session";
import { parseGenerateTryOnRequest, type ParsedGenerateTryOnRequest } from "./lib/tryOn/validation";

/**
 * `generateTryOn` (callable) - Phase 9.3 Stage 4.
 *
 * Trusted server-side Virtual Try-On generation. Requires an authenticated
 * Firebase user, explicit per-request consent (D5), and a product/colour/size
 * combination that resolves to a renderable, product-owned garment asset
 * (re-implements the Dart `hasRenderableVtoAsset` contract server-side - the
 * Admin SDK bypasses `firestore.rules`, so this check IS the real gate).
 *
 * Flow:
 *   1. Parse + validate the request (pure, no I/O).
 *   2. Resolve product eligibility + the exact garment asset for the
 *      requested colour (one Firestore read, no quota spent on a request
 *      that was never going to reach the provider anyway).
 *   3. ONE transaction: classify a retry of the same `(uid, idempotencyKey)`,
 *      or check-and-bump the D9 per-user/global rate-limit counters and
 *      create the `pending` session - the real cost circuit breaker, BEFORE
 *      any provider call.
 *   4. Read + re-verify (signature, and for the garment: size/hash too) the
 *      customer's own person-photo upload and the garment asset from
 *      Storage, call the provider (bounded timeout, no retry), re-verify +
 *      write the result, mark the session `succeeded`.
 *   5. `finally`: unconditionally delete the person upload - success or ANY
 *      failure, at ANY stage from step 2 onward (2026-09-11 hardening -
 *      previously this only ran once generation itself began, leaving an
 *      uploaded-but-never-used photo behind on an eligibility/rate-limit/
 *      idempotency refusal) - never retained, never logged, never sent
 *      anywhere but the provider.
 *
 * Every exit that is not an already-mapped, customer-safe `HttpsError` (an
 * unexpected Firestore/Storage fault at any point) is caught once at the top
 * level, best-effort marks the session `failed`, and is surfaced as a clean
 * `INTERNAL` error - a session can no longer be silently left stuck in
 * `pending`/`generating` by a fault this handler didn't anticipate (the
 * `cleanupExpiredTryOnMedia` stuck-session sweep is the remaining backstop
 * for the rare case where even that best-effort mark also fails).
 *
 * A retry with the SAME idempotency key after a success returns the cached
 * result (its REAL stored expiry, never "now") with NO new provider call;
 * after a failure it is refused (`SESSION_ATTEMPT_CLOSED`) so the caller must
 * mint a fresh key - together with the transactional rate limit, this is what
 * makes "duplicate requests must not be created" (UC-15 4B) actually true.
 */

export interface GenerateTryOnResult {
  sessionId: string;
  status: "succeeded";
  resultPath: string;
  expiresAt: number;
  provider: string;
  providerModel: string;
}

export interface GenerateTryOnHandlerInput {
  authUid: string | undefined;
  data: unknown;
  /** Injectable provider - production binds `geminiProvider(geminiApiKey.value())`;
   *  every automated test injects a fake that makes zero network calls. */
  provider: VtoProvider;
  /** Injectable clock for tests. */
  now?: () => number;
}

async function markFailed(sessionId: string, reason: string): Promise<void> {
  await tryOnSessionDoc(sessionId)
    .update({ status: "failed", failureReason: reason, updatedAt: FieldValue.serverTimestamp() })
    .catch((err) => logUnexpected("generateTryOn: could not mark session failed", err, { sessionId }));
}

function isSupportedPhotoType(contentType: string): boolean {
  return contentType === "image/jpeg" || contentType === "image/png";
}

function mapProviderError(err: unknown): { reason: string; httpsError: HttpsError } {
  if (err instanceof VtoProviderError) {
    switch (err.kind) {
      case "timeout":
        return { reason: "timeout", httpsError: errTimeout() };
      case "safety_block":
        return { reason: "provider_refused", httpsError: errProviderRefused() };
      case "auth":
      case "network":
      case "bad_response":
        return { reason: "provider_unavailable", httpsError: errProviderUnavailable() };
    }
  }
  logUnexpected("generateTryOn: unexpected provider error", err);
  return { reason: "internal", httpsError: errInternal() };
}

/**
 * The generation phase for a freshly-created `pending` session: flips it to
 * `generating`, reads + re-verifies the person photo and the garment asset,
 * calls the provider, re-verifies + writes the result, and marks the session
 * `succeeded`. Every raw (non-`HttpsError`) failure propagates to the
 * caller's top-level catch-all; every explicitly-handled failure here has
 * already called {@link markFailed} with a specific reason before throwing.
 */
async function runGeneration(args: {
  uid: string;
  sessionId: string;
  garment: ResolvedGarment;
  request: ParsedGenerateTryOnRequest;
  provider: VtoProvider;
  nowMs: number;
}): Promise<GenerateTryOnResult> {
  const { uid, sessionId, garment, request, provider, nowMs } = args;

  await tryOnSessionDoc(sessionId).update({
    status: "generating",
    updatedAt: FieldValue.serverTimestamp(),
  });

  const person = await readObjectBytes(tryOnUploadPath(uid, sessionId));
  if (!person) {
    await markFailed(sessionId, "missing_photo");
    throw errPhotoMissing();
  }
  if (
    !isSupportedPhotoType(person.contentType) ||
    person.size <= 0 ||
    person.size > VTO_PERSON_PHOTO_MAX_BYTES
  ) {
    await markFailed(sessionId, "invalid_photo");
    throw errPhotoInvalid();
  }
  if (!bytesMatchDeclaredType(person.bytes, person.contentType)) {
    // storage.rules can only assert the DECLARED contentType metadata on
    // upload, never the actual bytes - re-verify the real signature here,
    // before any billable provider call, so a mislabelled/non-image upload
    // is never forwarded to the paid provider.
    await markFailed(sessionId, "invalid_photo");
    logUnexpected("generateTryOn: person photo failed signature re-verification", null, { sessionId });
    throw errPhotoInvalid();
  }

  const garmentObject = await readObjectBytes(garment.storagePath);
  if (!garmentObject) {
    await markFailed(sessionId, "garment_missing");
    throw errGarmentUnavailable();
  }
  const garmentSha256 = createHash("sha256").update(garmentObject.bytes).digest("hex");
  if (
    garmentObject.bytes.length !== garment.byteSize ||
    garmentObject.contentType !== garment.contentType ||
    garmentSha256 !== garment.sha256 ||
    !bytesMatchDeclaredType(garmentObject.bytes, garment.contentType)
  ) {
    // The Admin-authored garment asset's ACTUAL Storage bytes/metadata no
    // longer completely agree with its (already-validated) Firestore
    // record - a re-upload race, an out-of-band edit, or corruption. Checks
    // FOUR independent things: byte length, the Storage object's OWN
    // `contentType` metadata (previously unchecked - could silently diverge
    // from the Firestore record), the sha256, and the actual byte signature.
    // Never forward mismatched bytes/metadata to a paid provider call.
    await markFailed(sessionId, "garment_integrity_mismatch");
    logUnexpected("generateTryOn: garment asset failed integrity re-verification", null, {
      sessionId,
      productId: request.productId,
    });
    throw errGarmentUnavailable();
  }

  let generated: VtoGenerateResult;
  try {
    generated = await provider.generate({
      personBytes: person.bytes,
      personContentType: person.contentType,
      garmentBytes: garmentObject.bytes,
      // The VERIFIED authoritative type - proven above to agree with the
      // Firestore record, the Storage object's own metadata, AND the actual
      // byte signature - never the raw (unverified-on-its-own) Storage
      // metadata value.
      garmentContentType: garment.contentType,
      garmentCategory: garment.garmentCategory,
      sizeHint: request.size,
    });
  } catch (err) {
    const mapped = mapProviderError(err);
    await markFailed(sessionId, mapped.reason);
    throw mapped.httpsError;
  }

  if (generated.imageBytes.length === 0 || generated.imageBytes.length > VTO_RESULT_MAX_BYTES) {
    await markFailed(sessionId, "invalid_result");
    throw errInternal();
  }
  const sniffedResultType = sniffImageContentType(generated.imageBytes);
  if (sniffedResultType === null || sniffedResultType !== generated.contentType) {
    // The provider's declared output contentType doesn't match its actual
    // bytes (or the bytes aren't a recognised image at all) - never save or
    // serve unverified provider output.
    await markFailed(sessionId, "invalid_result");
    logUnexpected("generateTryOn: provider output failed signature re-verification", null, { sessionId });
    throw errProviderUnavailable();
  }
  const ext = extensionForContentType(sniffedResultType);
  if (!ext) {
    // Unreachable - sniffImageContentType only ever returns a type
    // extensionForContentType also supports - but fail closed, never assume.
    await markFailed(sessionId, "invalid_result");
    throw errInternal();
  }

  // The result is saved under the extension matching its VERIFIED actual
  // content type (Gemini image output is commonly PNG) - never under a
  // misleading `.jpg` name regardless of format.
  const resultPath = tryOnResultPath(uid, sessionId, ext);
  try {
    await writeObjectBytes(resultPath, generated.imageBytes, sniffedResultType);
  } catch (err) {
    logUnexpected("generateTryOn: writing the result to Storage failed", err, { sessionId });
    await markFailed(sessionId, "internal_error");
    throw errInternal();
  }

  const expiresAtMs = nowMs + VTO_RESULT_TTL_MS;
  try {
    await tryOnSessionDoc(sessionId).update({
      status: "succeeded",
      resultPath,
      failureReason: null,
      expiresAt: Timestamp.fromMillis(expiresAtMs),
      updatedAt: FieldValue.serverTimestamp(),
    });
  } catch (err) {
    // The Firestore write is authoritative for what "succeeded" means - an
    // object with no confirming session record must never be left behind.
    await deleteObjectBestEffort(resultPath, "generateTryOn");
    await markFailed(sessionId, "internal_error").catch(() => undefined);
    logUnexpected(
      "generateTryOn: marking session succeeded failed after writing the result - rolled back",
      err,
      { sessionId },
    );
    throw errInternal();
  }

  return {
    sessionId,
    status: "succeeded",
    resultPath,
    expiresAt: expiresAtMs,
    provider: VTO_PROVIDER_NAME,
    providerModel: VTO_PROVIDER_MODEL,
  };
}

export async function generateTryOnHandler(
  input: GenerateTryOnHandlerInput,
): Promise<GenerateTryOnResult> {
  const nowMs = (input.now ?? Date.now)();

  if (!input.authUid) {
    throw errUnauthenticated();
  }
  const uid = input.authUid;

  const request = parseGenerateTryOnRequest(input.data);
  const sessionId = tryOnSessionIdFor(uid, request.idempotencyKey);
  const uploadPath = tryOnUploadPath(uid, sessionId);

  try {
    // Eligibility FIRST - a request that was never going to reach the
    // provider (unknown/ineligible product, unavailable variant, missing
    // garment asset) spends no rate-limit quota.
    const productSnap = await productDoc(request.productId).get();
    if (!productSnap.exists) {
      throw errProductUnavailable();
    }
    const garment = resolveEligibleGarment(
      request.productId,
      (productSnap.data() ?? {}) as Record<string, unknown>,
      request.colorKey,
      request.size,
    );

    const outcome = await reserveTryOnSessionOrClassify({ uid, sessionId, request, garment, nowMs });

    if (outcome.kind === "succeeded_cached") {
      return {
        sessionId,
        status: "succeeded",
        resultPath: outcome.resultPath,
        expiresAt: outcome.expiresAtMs,
        provider: VTO_PROVIDER_NAME,
        providerModel: VTO_PROVIDER_MODEL,
      };
    }

    // outcome.kind === "created": a fresh `pending` session now exists and
    // the rate-limit counters are already bumped.
    return await runGeneration({ uid, sessionId, garment, request, provider: input.provider, nowMs });
  } catch (err) {
    if (err instanceof HttpsError) {
      // Already a mapped, customer-safe error - and every branch that threw
      // one from a point where a session actually existed already called
      // `markFailed` itself with a specific reason.
      throw err;
    }
    // Genuinely unexpected (e.g. a raw Firestore/Storage exception with no
    // dedicated handling above) - never leave a session silently stuck.
    logUnexpected("generateTryOn: unexpected failure", err, { sessionId });
    await markFailed(sessionId, "internal_error").catch(() => undefined);
    throw errInternal();
  } finally {
    // D4: unconditional - every exit past this point, success or ANY
    // failure at ANY stage, deletes the person photo right here, every
    // time. Never retained past this single invocation.
    await deleteObjectBestEffort(uploadPath, "generateTryOn");
  }
}

export const generateTryOn = onCall(
  {
    region: FUNCTIONS_REGION,
    secrets: [geminiApiKey],
    memory: "512MiB",
    timeoutSeconds: 120,
    // Bounds worst-case concurrent provider spend exposure alongside the D9
    // server-enforced quota transaction (the real cost stop).
    maxInstances: 20,
  },
  (request) =>
    generateTryOnHandler({
      authUid: request.auth?.uid,
      data: request.data,
      provider: geminiProvider(geminiApiKey.value()),
    }),
);
