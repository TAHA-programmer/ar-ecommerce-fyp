import {
  errProductUnavailable,
  errVariantUnavailable,
} from "./errors";

/**
 * Authoritative reads off a `products/{id}` Firestore document.
 *
 * The Cloud Function uses the Admin SDK, which bypasses the
 * `products/{id}` read rule (`published && isActive`), so these checks are
 * re-implemented here as the real gate. Field coercion mirrors
 * `product_firestore_mapper.dart` (`(x as num?)?.toInt() ?? 0`, defensive).
 *
 * Pure - operates on the already-fetched document data.
 */

function toIntOrZero(value: unknown): number {
  return typeof value === "number" && Number.isFinite(value) ? Math.trunc(value) : 0;
}

export function productPriceRupees(data: Record<string, unknown>): number {
  // `priceAmount` is the current selling price (what `CheckoutViewModel`
  // parses from `summary.currentPrice`). `originalPriceAmount` is the
  // struck-through "was" price and is never charged.
  const price = toIntOrZero(data.priceAmount);
  return price;
}

export function productStockQuantity(data: Record<string, unknown>): number {
  return toIntOrZero(data.stockQuantity);
}

export function productTitle(data: Record<string, unknown>): string {
  return typeof data.title === "string" ? data.title : "";
}

export interface ProductImageSnapshot {
  imagePath: string;
  imageSource: string;
}

export function productMainImage(data: Record<string, unknown>): ProductImageSnapshot {
  const main = data.mainImage;
  if (main && typeof main === "object") {
    const m = main as Record<string, unknown>;
    return {
      imagePath: typeof m.path === "string" ? m.path : "",
      imageSource: typeof m.source === "string" ? m.source : "network",
    };
  }
  return { imagePath: "", imageSource: "network" };
}

/**
 * Throw `PRODUCT_UNAVAILABLE` unless the product is `published && isActive`.
 * A missing document is the caller's responsibility to detect first (it also
 * throws `PRODUCT_UNAVAILABLE`).
 */
export function assertProductPurchasable(
  productId: string,
  data: Record<string, unknown>,
): void {
  const published = data.publicationStatus === "published";
  const active = data.isActive === true;
  if (!published || !active) {
    throw errProductUnavailable(productId, productTitle(data) || undefined);
  }
}

function stringListContains(value: unknown, target: string): boolean {
  return (
    Array.isArray(value) &&
    value.some((entry) => typeof entry === "string" && entry === target)
  );
}

/**
 * Lenient variant check: only reject when the product *declares* a non-empty
 * option list for that dimension AND the requested value isn't in it. A
 * product that declares no colours/sizes accepts any (legacy tolerance);
 * a `null` requested value is always fine.
 */
export function assertVariantAvailable(
  productId: string,
  data: Record<string, unknown>,
  line: { selectedColor: string | null; selectedSize: string | null },
): void {
  const colours = data.availableColors;
  if (
    line.selectedColor !== null &&
    Array.isArray(colours) &&
    colours.length > 0 &&
    !stringListContains(colours, line.selectedColor)
  ) {
    throw errVariantUnavailable(productId, productTitle(data) || undefined);
  }

  const sizes = data.availableSizes;
  if (
    line.selectedSize !== null &&
    Array.isArray(sizes) &&
    sizes.length > 0 &&
    !stringListContains(sizes, line.selectedSize)
  ) {
    throw errVariantUnavailable(productId, productTitle(data) || undefined);
  }
}
