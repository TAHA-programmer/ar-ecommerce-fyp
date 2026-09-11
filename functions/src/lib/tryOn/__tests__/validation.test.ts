import { describe, expect, it } from "vitest";

import { parseGenerateTryOnRequest } from "../validation";

function validBody(overrides: Record<string, unknown> = {}) {
  return {
    productId: "mens-oxford-shirt",
    colorKey: "blue",
    size: "L",
    idempotencyKey: "idem-key-12345678",
    consent: true,
    ...overrides,
  };
}

function expectAppCode(fn: () => unknown, appCode: string) {
  try {
    fn();
  } catch (err) {
    const details = (err as { details?: Record<string, unknown> }).details ?? {};
    expect(details.appCode).toBe(appCode);
    return;
  }
  throw new Error(`expected to throw with appCode ${appCode}`);
}

describe("parseGenerateTryOnRequest - happy path", () => {
  it("accepts a fully valid request", () => {
    const parsed = parseGenerateTryOnRequest(validBody());
    expect(parsed).toEqual({
      productId: "mens-oxford-shirt",
      colorKey: "blue",
      size: "L",
      idempotencyKey: "idem-key-12345678",
    });
  });

  it("accepts a null/absent/empty size as null (soft hint only)", () => {
    expect(parseGenerateTryOnRequest(validBody({ size: null })).size).toBeNull();
    expect(parseGenerateTryOnRequest(validBody({ size: undefined })).size).toBeNull();
    expect(parseGenerateTryOnRequest(validBody({ size: "" })).size).toBeNull();
  });
});

describe("parseGenerateTryOnRequest - shape", () => {
  it("rejects a non-object body", () => {
    expectAppCode(() => parseGenerateTryOnRequest("nonsense"), "INVALID_REQUEST");
    expectAppCode(() => parseGenerateTryOnRequest(null), "INVALID_REQUEST");
    expectAppCode(() => parseGenerateTryOnRequest([1, 2]), "INVALID_REQUEST");
  });

  it("rejects a missing/empty/oversized productId", () => {
    expectAppCode(() => parseGenerateTryOnRequest(validBody({ productId: undefined })), "INVALID_REQUEST");
    expectAppCode(() => parseGenerateTryOnRequest(validBody({ productId: "" })), "INVALID_REQUEST");
    expectAppCode(
      () => parseGenerateTryOnRequest(validBody({ productId: "x".repeat(201) })),
      "INVALID_REQUEST",
    );
  });

  it("rejects a productId that looks like a path (defence in depth)", () => {
    expectAppCode(() => parseGenerateTryOnRequest(validBody({ productId: "a/b" })), "INVALID_REQUEST");
    expectAppCode(() => parseGenerateTryOnRequest(validBody({ productId: ".." })), "INVALID_REQUEST");
  });

  it("rejects a missing/empty/oversized colorKey", () => {
    expectAppCode(() => parseGenerateTryOnRequest(validBody({ colorKey: undefined })), "INVALID_REQUEST");
    expectAppCode(() => parseGenerateTryOnRequest(validBody({ colorKey: "" })), "INVALID_REQUEST");
    expectAppCode(
      () => parseGenerateTryOnRequest(validBody({ colorKey: "x".repeat(41) })),
      "INVALID_REQUEST",
    );
  });

  it("rejects a non-string size", () => {
    expectAppCode(() => parseGenerateTryOnRequest(validBody({ size: 42 })), "INVALID_REQUEST");
  });

  it("rejects a too-short / too-long / missing idempotencyKey", () => {
    expectAppCode(() => parseGenerateTryOnRequest(validBody({ idempotencyKey: "short" })), "INVALID_REQUEST");
    expectAppCode(() => parseGenerateTryOnRequest(validBody({ idempotencyKey: undefined })), "INVALID_REQUEST");
    expectAppCode(
      () => parseGenerateTryOnRequest(validBody({ idempotencyKey: "x".repeat(201) })),
      "INVALID_REQUEST",
    );
  });
});

describe("parseGenerateTryOnRequest - consent (D5)", () => {
  it("rejects a missing consent flag", () => {
    expectAppCode(() => parseGenerateTryOnRequest(validBody({ consent: undefined })), "CONSENT_REQUIRED");
  });

  it("rejects consent: false", () => {
    expectAppCode(() => parseGenerateTryOnRequest(validBody({ consent: false })), "CONSENT_REQUIRED");
  });

  it("rejects a truthy-but-non-boolean consent value (e.g. a stale cached '1')", () => {
    expectAppCode(() => parseGenerateTryOnRequest(validBody({ consent: 1 })), "CONSENT_REQUIRED");
    expectAppCode(() => parseGenerateTryOnRequest(validBody({ consent: "true" })), "CONSENT_REQUIRED");
  });

  it("cannot be smuggled in via an extra unrelated field name", () => {
    const body = validBody({ consent: undefined, consentGiven: true, agreedToConsent: true });
    expectAppCode(() => parseGenerateTryOnRequest(body), "CONSENT_REQUIRED");
  });
});
