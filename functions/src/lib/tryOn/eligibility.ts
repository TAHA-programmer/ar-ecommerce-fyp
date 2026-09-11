import {
  errGarmentUnavailable,
  errProductNotEligible,
  errProductUnavailable,
  errVariantUnavailable,
} from "./errors";

/**
 * Server-side re-implementation of the Dart Virtual Try-On eligibility
 * contract (`ProductVtoMetadata` / `ProductModel.hasRenderableVtoAsset` in
 * `lib/core/models/product/product_vto_metadata.dart` / `product_model.dart`).
 *
 * The Admin SDK bypasses `firestore.rules`, so these checks ARE the real
 * gate - exactly the same reasoning as `../product.ts` for checkout. A
 * product/garment that the customer app itself would refuse to render can
 * never reach the provider here either. Pure - operates on already-fetched
 * document data.
 */

const SUPPORTED_GARMENT_CATEGORIES: ReadonlySet<string> = new Set([
  "top",
  "outerwear",
  "dress",
  "bottom",
]);

const SUPPORTED_CONTENT_TYPES: ReadonlySet<string> = new Set(["image/jpeg", "image/png"]);

export interface ResolvedGarment {
  storagePath: string;
  contentType: string;
  garmentCategory: string;
  /** The Firestore-recorded SHA-256 (64 lowercase hex) - re-verified against
   *  the actual downloaded Storage bytes before every provider call. */
  sha256: string;
  /** The Firestore-recorded byte size - re-verified against the actual
   *  downloaded object size before every provider call. */
  byteSize: number;
}

function toStr(v: unknown): string {
  return typeof v === "string" ? v.trim() : "";
}

function toIntStrict(v: unknown): number {
  if (typeof v === "number" && Number.isFinite(v) && Number.isInteger(v)) return v;
  return -1;
}

function fileExt(contentType: string): "jpg" | "png" | null {
  if (contentType === "image/png") return "png";
  if (contentType === "image/jpeg") return "jpg";
  return null;
}

interface RawGarmentAsset {
  storagePath: string;
  sha256: string;
  contentType: string;
  byteSize: number;
  width: number;
  height: number;
  version: number;
}

function parseGarmentAsset(raw: unknown): RawGarmentAsset | null {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return null;
  const map = raw as Record<string, unknown>;
  const storagePath = toStr(map.storagePath);
  if (storagePath.length === 0) return null;
  return {
    storagePath,
    sha256: toStr(map.sha256),
    contentType: toStr(map.contentType).toLowerCase(),
    byteSize: toIntStrict(map.byteSize),
    width: toIntStrict(map.width),
    height: toIntStrict(map.height),
    version: toIntStrict(map.version),
  };
}

const SHA256_RE = /^[0-9a-f]{64}$/;
const MAX_ASSET_BYTES = 12 * 1024 * 1024;

/** Mirrors `VtoGarmentAsset.isRenderable` (issues.isEmpty). */
function assetIsRenderable(asset: RawGarmentAsset): boolean {
  return (
    SHA256_RE.test(asset.sha256) &&
    SUPPORTED_CONTENT_TYPES.has(asset.contentType) &&
    asset.byteSize > 0 &&
    asset.byteSize <= MAX_ASSET_BYTES &&
    asset.width > 0 &&
    asset.height > 0 &&
    asset.version >= 1
  );
}

/** Mirrors `VtoGarmentAsset.matchesExpectedPath(productId, slot)`. */
function assetMatchesExpectedPath(productId: string, slot: string, asset: RawGarmentAsset): boolean {
  const ext = fileExt(asset.contentType);
  if (!ext) return false;
  return asset.storagePath === `products/${productId}/vto/garment-${slot}-v${asset.version}.${ext}`;
}

/**
 * Resolve the exact garment asset `generateTryOn` may use for
 * `(productId, colorKey, size)`, or throw a customer-safe error. ALL of the
 * following must hold, mirroring `hasRenderableVtoAsset` exactly:
 *   - `experienceType == 'virtualTryOn'`
 *   - `publicationStatus == 'published' && isActive == true`
 *   - `vtoDisabled` is not `true`
 *   - the VTO contract id + garment category are present and well-formed
 *   - `colorKey` resolves to a renderable asset (its own entry, or the
 *     product-wide default) that PROVABLY belongs to this product (the same
 *     `assetsBelongToProduct` ownership defence as the Dart contract) - never
 *     a well-formed-but-foreign / hand-edited / cross-product path
 *   - `size`, when the product declares a non-empty `availableSizes` list,
 *     is one of them (lenient like `assertVariantAvailable` - a `null` size
 *     is always accepted, it is a soft styling hint only, never a fit input)
 */
export function resolveEligibleGarment(
  productId: string,
  data: Record<string, unknown>,
  colorKey: string,
  size: string | null,
): ResolvedGarment {
  const published = data.publicationStatus === "published";
  const active = data.isActive === true;
  if (!published || !active) {
    throw errProductUnavailable();
  }

  const experienceType = data.experienceType;
  if (experienceType !== "virtualTryOn") {
    throw errProductNotEligible();
  }
  if (data.vtoDisabled === true) {
    throw errProductNotEligible();
  }

  const garmentCategory = toStr(data.vtoGarmentCategory).toLowerCase();
  const contract = toStr(data.vtoContract);
  if (contract.length === 0 || !SUPPORTED_GARMENT_CATEGORIES.has(garmentCategory)) {
    throw errProductNotEligible();
  }

  const sizes = data.availableSizes;
  if (
    size !== null &&
    Array.isArray(sizes) &&
    sizes.length > 0 &&
    !sizes.some((s) => typeof s === "string" && s === size)
  ) {
    throw errVariantUnavailable();
  }

  const colours = data.availableColors;
  if (
    Array.isArray(colours) &&
    colours.length > 0 &&
    !colours.some((c) => typeof c === "string" && c === colorKey)
  ) {
    throw errVariantUnavailable();
  }

  const rawGarments = data.vtoGarments;
  const perColor =
    rawGarments && typeof rawGarments === "object" && !Array.isArray(rawGarments)
      ? (rawGarments as Record<string, unknown>)[colorKey]
      : undefined;

  let asset = parseGarmentAsset(perColor);
  let slot = colorKey;
  if (!asset || !assetIsRenderable(asset) || !assetMatchesExpectedPath(productId, slot, asset)) {
    const defaultAsset = parseGarmentAsset(data.vtoGarmentDefault);
    if (
      defaultAsset &&
      assetIsRenderable(defaultAsset) &&
      assetMatchesExpectedPath(productId, "default", defaultAsset)
    ) {
      asset = defaultAsset;
      slot = "default";
    } else {
      asset = null;
    }
  }

  if (!asset) {
    throw errGarmentUnavailable();
  }

  return {
    storagePath: asset.storagePath,
    contentType: asset.contentType,
    garmentCategory,
    sha256: asset.sha256,
    byteSize: asset.byteSize,
  };
}
