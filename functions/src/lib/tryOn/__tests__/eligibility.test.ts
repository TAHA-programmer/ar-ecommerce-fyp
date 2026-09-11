import { describe, expect, it } from "vitest";

import { resolveEligibleGarment } from "../eligibility";

const PRODUCT_ID = "mens-oxford-shirt";
const SHA = "a".repeat(64);

function garmentAsset(overrides: Record<string, unknown> = {}) {
  return {
    storagePath: `products/${PRODUCT_ID}/vto/garment-blue-v1.jpg`,
    sha256: SHA,
    contentType: "image/jpeg",
    byteSize: 100_000,
    width: 900,
    height: 1200,
    version: 1,
    ...overrides,
  };
}

function validProductDoc(overrides: Record<string, unknown> = {}) {
  return {
    publicationStatus: "published",
    isActive: true,
    experienceType: "virtualTryOn",
    vtoDisabled: false,
    vtoContract: "twin-ar/vto-contract-9.3",
    vtoGarmentCategory: "top",
    availableColors: ["blue", "black"],
    availableSizes: ["S", "M", "L"],
    vtoGarments: { blue: garmentAsset() },
    ...overrides,
  };
}

function expectAppCode(fn: () => unknown, appCode: string) {
  try {
    fn();
  } catch (err) {
    const details = (err as { details?: Record<string, unknown> }).details ?? {};
    expect(details.appCode, `expected ${appCode}, got: ${JSON.stringify(err)}`).toBe(appCode);
    return;
  }
  throw new Error(`expected to throw with appCode ${appCode}`);
}

describe("resolveEligibleGarment - happy path", () => {
  it("resolves the exact per-colour asset", () => {
    const r = resolveEligibleGarment(PRODUCT_ID, validProductDoc(), "blue", "L");
    expect(r).toEqual({
      storagePath: `products/${PRODUCT_ID}/vto/garment-blue-v1.jpg`,
      contentType: "image/jpeg",
      garmentCategory: "top",
      sha256: SHA,
      byteSize: 100_000,
    });
  });

  it("accepts a null size (soft hint only)", () => {
    expect(() => resolveEligibleGarment(PRODUCT_ID, validProductDoc(), "blue", null)).not.toThrow();
  });

  it("falls back to the product-wide default when a colour has no dedicated asset", () => {
    const doc = validProductDoc({
      vtoGarments: {},
      vtoGarmentDefault: garmentAsset({
        storagePath: `products/${PRODUCT_ID}/vto/garment-default-v1.jpg`,
      }),
    });
    const r = resolveEligibleGarment(PRODUCT_ID, doc, "black", "M");
    expect(r.storagePath).toBe(`products/${PRODUCT_ID}/vto/garment-default-v1.jpg`);
  });

  it("accepts any colourKey when the product declares no availableColors at all (legacy tolerance)", () => {
    const doc = validProductDoc({ availableColors: [], vtoGarments: { red: garmentAsset({
      storagePath: `products/${PRODUCT_ID}/vto/garment-red-v1.jpg`,
    }) } });
    expect(() => resolveEligibleGarment(PRODUCT_ID, doc, "red", null)).not.toThrow();
  });
});

describe("resolveEligibleGarment - product-level gates", () => {
  it("PRODUCT_UNAVAILABLE for a draft product", () => {
    expectAppCode(
      () => resolveEligibleGarment(PRODUCT_ID, validProductDoc({ publicationStatus: "draft" }), "blue", null),
      "PRODUCT_UNAVAILABLE",
    );
  });

  it("PRODUCT_UNAVAILABLE for an inactive product", () => {
    expectAppCode(
      () => resolveEligibleGarment(PRODUCT_ID, validProductDoc({ isActive: false }), "blue", null),
      "PRODUCT_UNAVAILABLE",
    );
  });

  it("PRODUCT_NOT_ELIGIBLE when experienceType is not virtualTryOn", () => {
    expectAppCode(
      () => resolveEligibleGarment(PRODUCT_ID, validProductDoc({ experienceType: "roomAr" }), "blue", null),
      "PRODUCT_NOT_ELIGIBLE",
    );
    expectAppCode(
      () => resolveEligibleGarment(PRODUCT_ID, validProductDoc({ experienceType: "none" }), "blue", null),
      "PRODUCT_NOT_ELIGIBLE",
    );
  });

  it("PRODUCT_NOT_ELIGIBLE when the admin has disabled the VTO entry point", () => {
    expectAppCode(
      () => resolveEligibleGarment(PRODUCT_ID, validProductDoc({ vtoDisabled: true }), "blue", null),
      "PRODUCT_NOT_ELIGIBLE",
    );
  });

  it("PRODUCT_NOT_ELIGIBLE when the vto contract id is missing", () => {
    expectAppCode(
      () => resolveEligibleGarment(PRODUCT_ID, validProductDoc({ vtoContract: "" }), "blue", null),
      "PRODUCT_NOT_ELIGIBLE",
    );
  });

  it("PRODUCT_NOT_ELIGIBLE for an unsupported garment category", () => {
    expectAppCode(
      () => resolveEligibleGarment(PRODUCT_ID, validProductDoc({ vtoGarmentCategory: "shoes" }), "blue", null),
      "PRODUCT_NOT_ELIGIBLE",
    );
  });
});

describe("resolveEligibleGarment - variant checks", () => {
  it("VARIANT_UNAVAILABLE for a colour the product does not declare", () => {
    expectAppCode(
      () => resolveEligibleGarment(PRODUCT_ID, validProductDoc(), "pink", null),
      "VARIANT_UNAVAILABLE",
    );
  });

  it("VARIANT_UNAVAILABLE for a size the product does not declare", () => {
    expectAppCode(
      () => resolveEligibleGarment(PRODUCT_ID, validProductDoc(), "blue", "XXL"),
      "VARIANT_UNAVAILABLE",
    );
  });
});

describe("resolveEligibleGarment - garment asset checks", () => {
  it("GARMENT_UNAVAILABLE when no asset exists for the colour and there is no default", () => {
    expectAppCode(
      () => resolveEligibleGarment(PRODUCT_ID, validProductDoc(), "black", null),
      "GARMENT_UNAVAILABLE",
    );
  });

  it("GARMENT_UNAVAILABLE for a malformed sha256", () => {
    const doc = validProductDoc({ vtoGarments: { blue: garmentAsset({ sha256: "not-hex" }) } });
    expectAppCode(() => resolveEligibleGarment(PRODUCT_ID, doc, "blue", null), "GARMENT_UNAVAILABLE");
  });

  it("GARMENT_UNAVAILABLE for an unsupported content type", () => {
    const doc = validProductDoc({ vtoGarments: { blue: garmentAsset({ contentType: "model/gltf-binary" }) } });
    expectAppCode(() => resolveEligibleGarment(PRODUCT_ID, doc, "blue", null), "GARMENT_UNAVAILABLE");
  });

  it("GARMENT_UNAVAILABLE for a non-positive byteSize/width/height", () => {
    expectAppCode(
      () =>
        resolveEligibleGarment(
          PRODUCT_ID,
          validProductDoc({ vtoGarments: { blue: garmentAsset({ byteSize: 0 }) } }),
          "blue",
          null,
        ),
      "GARMENT_UNAVAILABLE",
    );
    expectAppCode(
      () =>
        resolveEligibleGarment(
          PRODUCT_ID,
          validProductDoc({ vtoGarments: { blue: garmentAsset({ width: 0 }) } }),
          "blue",
          null,
        ),
      "GARMENT_UNAVAILABLE",
    );
  });

  it("GARMENT_UNAVAILABLE for a storage path that belongs to ANOTHER product (cross-product ownership defence)", () => {
    const doc = validProductDoc({
      vtoGarments: { blue: garmentAsset({ storagePath: "products/some-other-product/vto/garment-blue-v1.jpg" }) },
    });
    expectAppCode(() => resolveEligibleGarment(PRODUCT_ID, doc, "blue", null), "GARMENT_UNAVAILABLE");
  });

  it("GARMENT_UNAVAILABLE for a hand-edited path with the wrong version number", () => {
    const doc = validProductDoc({
      vtoGarments: {
        blue: garmentAsset({ storagePath: `products/${PRODUCT_ID}/vto/garment-blue-v1.jpg`, version: 2 }),
      },
    });
    expectAppCode(() => resolveEligibleGarment(PRODUCT_ID, doc, "blue", null), "GARMENT_UNAVAILABLE");
  });

  it("GARMENT_UNAVAILABLE for a path under the wrong colour slot", () => {
    const doc = validProductDoc({
      vtoGarments: { blue: garmentAsset({ storagePath: `products/${PRODUCT_ID}/vto/garment-black-v1.jpg` }) },
    });
    expectAppCode(() => resolveEligibleGarment(PRODUCT_ID, doc, "blue", null), "GARMENT_UNAVAILABLE");
  });

  it("falls back to a valid default when the per-colour entry is foreign/broken", () => {
    const doc = validProductDoc({
      vtoGarments: { blue: garmentAsset({ storagePath: "products/foreign/vto/garment-blue-v1.jpg" }) },
      vtoGarmentDefault: garmentAsset({ storagePath: `products/${PRODUCT_ID}/vto/garment-default-v1.jpg` }),
    });
    const r = resolveEligibleGarment(PRODUCT_ID, doc, "blue", null);
    expect(r.storagePath).toBe(`products/${PRODUCT_ID}/vto/garment-default-v1.jpg`);
  });

  it("GARMENT_UNAVAILABLE when BOTH the per-colour entry and the default are foreign", () => {
    const doc = validProductDoc({
      vtoGarments: { blue: garmentAsset({ storagePath: "products/foreign/vto/garment-blue-v1.jpg" }) },
      vtoGarmentDefault: garmentAsset({ storagePath: "products/foreign/vto/garment-default-v1.jpg" }),
    });
    expectAppCode(() => resolveEligibleGarment(PRODUCT_ID, doc, "blue", null), "GARMENT_UNAVAILABLE");
  });

  it("GARMENT_UNAVAILABLE when vtoGarments is present but not a map", () => {
    const doc = validProductDoc({ vtoGarments: "not-a-map" });
    expectAppCode(() => resolveEligibleGarment(PRODUCT_ID, doc, "blue", null), "GARMENT_UNAVAILABLE");
  });
});
