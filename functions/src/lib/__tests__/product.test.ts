import { describe, it, expect } from "vitest";

import {
  assertProductPurchasable,
  assertVariantAvailable,
  productMainImage,
  productPriceRupees,
  productStockQuantity,
  productTitle,
} from "../product";

const purchasable = {
  title: "Test Chair",
  priceAmount: 12000,
  originalPriceAmount: 15000,
  stockQuantity: 4,
  isActive: true,
  publicationStatus: "published",
  mainImage: { path: "products/p1/main.jpg", source: "network" },
  availableColors: ["black", "walnut"],
  availableSizes: [],
};

describe("product field readers", () => {
  it("reads price/stock/title/image with defensive coercion", () => {
    expect(productPriceRupees(purchasable)).toBe(12000);
    expect(productStockQuantity(purchasable)).toBe(4);
    expect(productTitle(purchasable)).toBe("Test Chair");
    expect(productMainImage(purchasable)).toEqual({
      imagePath: "products/p1/main.jpg",
      imageSource: "network",
    });
  });

  it("never charges originalPriceAmount", () => {
    expect(productPriceRupees(purchasable)).not.toBe(purchasable.originalPriceAmount);
  });

  it("coerces missing / wrong-typed numbers to 0 and truncates floats", () => {
    expect(productPriceRupees({})).toBe(0);
    expect(productStockQuantity({ stockQuantity: "5" })).toBe(0);
    expect(productStockQuantity({ stockQuantity: 3.9 })).toBe(3);
    expect(productMainImage({})).toEqual({ imagePath: "", imageSource: "network" });
  });
});

describe("assertProductPurchasable", () => {
  it("passes a published + active product", () => {
    expect(() => assertProductPurchasable("p1", purchasable)).not.toThrow();
  });
  it("rejects a draft product", () => {
    expect(() =>
      assertProductPurchasable("p1", { ...purchasable, publicationStatus: "draft" }),
    ).toThrow();
  });
  it("rejects an inactive product", () => {
    expect(() =>
      assertProductPurchasable("p1", { ...purchasable, isActive: false }),
    ).toThrow();
  });
});

describe("assertVariantAvailable (lenient)", () => {
  it("passes when the selected colour is offered", () => {
    expect(() =>
      assertVariantAvailable("p1", purchasable, { selectedColor: "black", selectedSize: null }),
    ).not.toThrow();
  });
  it("rejects a colour the product does not offer", () => {
    expect(() =>
      assertVariantAvailable("p1", purchasable, { selectedColor: "pink", selectedSize: null }),
    ).toThrow();
  });
  it("is lenient when the product declares no options for that dimension", () => {
    expect(() =>
      assertVariantAvailable("p1", purchasable, { selectedColor: null, selectedSize: "XL" }),
    ).not.toThrow(); // availableSizes is []
  });
  it("is lenient for a null selection", () => {
    expect(() =>
      assertVariantAvailable("p1", purchasable, { selectedColor: null, selectedSize: null }),
    ).not.toThrow();
  });
});
