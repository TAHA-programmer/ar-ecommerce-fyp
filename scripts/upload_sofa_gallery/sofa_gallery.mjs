// TWin AR — Phase 9.2 R14: the approved Luna Right-Chaise Sectional Sofa
// customer gallery (validated-GLB studio renders). Shared, single source of
// truth for BOTH the Stage-A uploader (upload_sofa_gallery.mjs) and the
// Stage-B catalogue recast (../migrate_ar_catalogue/lib.mjs), so the object
// paths / hashes / order never drift between the two.
//
// Content-hashed object names (`img-<sha16>.png`) match the Phase 8.7.1
// product-image migration convention exactly, so the Firestore `network`
// refs the recast writes are the same shape the app already consumes.

import { createHash } from 'node:crypto';
import { existsSync, readFileSync, statSync } from 'node:fs';
import path from 'node:path';

export const CONFIRMED_PROJECT_ID = 'twin-ar-d4d75';
export const STORAGE_BUCKET = `${CONFIRMED_PROJECT_ID}.firebasestorage.app`;
export const SOFA_PRODUCT_ID = 'luna-3-seater-sofa';

/** Every sofa gallery render is a PNG — the single source of truth for the
 *  content type expected in Storage, shared by the Stage-A uploader and the
 *  Stage-B catalogue-recast storage gate. */
export const SOFA_IMAGE_CONTENT_TYPE = 'image/png';

/** The custom Storage metadata key the Stage-B recast is gated on. An object
 *  without this key (or with the wrong value) is NOT considered fully staged,
 *  even when its bytes are already identical. */
export const SOFA_SHA256_METADATA_KEY = 'twinArSofaGallerySha256';

/** Larger than any render (top-plan ≈ 20 KB, hero ≈ 46 KB); matches storage.rules' 10 MB product-image ceiling. */
export const MAX_IMAGE_BYTES = 10 * 1024 * 1024;

const IMG_DIR = '_ar_assets/generated/renders';

/**
 * The six approved views, in customer gallery order. `role: 'main'` is also
 * written as `mainImage`. `expectedSha256` / `expectedSizeBytes` are the
 * exact bytes of the render on disk (re-verified at preflight); the tool
 * NEVER uploads bytes whose hash does not match.
 */
export const SOFA_GALLERY = [
  {
    sourceRelPath: `${IMG_DIR}/sofa_r_v1_cat_3q.png`,
    stableName: 'img-d8317097149c3f43.png',
    role: 'main',
    order: 0,
    altText: 'Luna Right-Chaise Sectional Sofa — three-quarter view',
    expectedSha256:
      'd8317097149c3f433da37c2af0b7bbf88fa34ac9e24da1000480eb98f8d922eb',
    expectedSizeBytes: 46000,
  },
  {
    sourceRelPath: `${IMG_DIR}/sofa_r_v1_front.png`,
    stableName: 'img-3403a887f40799f6.png',
    role: 'gallery',
    order: 1,
    altText: 'Luna Right-Chaise Sectional Sofa — front view',
    expectedSha256:
      '3403a887f40799f60a0f9d29710438defe539d9dd52f1ba01f7a6a3976829aa1',
    expectedSizeBytes: 25120,
  },
  {
    sourceRelPath: `${IMG_DIR}/sofa_r_v1_opp_3q.png`,
    stableName: 'img-2b280dd8bdb2077c.png',
    role: 'gallery',
    order: 2,
    altText: 'Luna Right-Chaise Sectional Sofa — opposite three-quarter view',
    expectedSha256:
      '2b280dd8bdb2077c39faf3aba9c2e229c5aa576c0fa2deca3a0d58007cb9b745',
    expectedSizeBytes: 41313,
  },
  {
    sourceRelPath: `${IMG_DIR}/sofa_r_v1_left_side.png`,
    stableName: 'img-0bc14afc44b19d36.png',
    role: 'gallery',
    order: 3,
    altText: 'Luna Right-Chaise Sectional Sofa — chaise-side profile',
    expectedSha256:
      '0bc14afc44b19d36a1811d8b8cbf14d32506a4a1b6c7ecbc449c350132ca694d',
    expectedSizeBytes: 18917,
  },
  {
    sourceRelPath: `${IMG_DIR}/sofa_r_v1_right_side.png`,
    stableName: 'img-ed7d709f1f16e1ac.png',
    role: 'gallery',
    order: 4,
    altText: 'Luna Right-Chaise Sectional Sofa — arm-side profile',
    expectedSha256:
      'ed7d709f1f16e1ac2945b7cfc1b0976e86abc3946711409bfbf29bea0f3165e0',
    expectedSizeBytes: 16981,
  },
  {
    sourceRelPath: `${IMG_DIR}/sofa_r_v1_top_plan.png`,
    stableName: 'img-cda9344a27622028.png',
    role: 'gallery',
    order: 5,
    altText: 'Luna Right-Chaise Sectional Sofa — plan / layout view',
    expectedSha256:
      'cda9344a27622028829ce135a7ad303fb3c5fa5242dd1cce7438d6e058a23531',
    expectedSizeBytes: 20644,
  },
];

export function objectPathFor(item) {
  return `products/${SOFA_PRODUCT_ID}/images/${item.stableName}`;
}

/** Public Firebase media URL — same shape `getDownloadURL()` and the Phase
 *  8.7.1 migration produce; `products/{id}/images/**` is public-read. */
export function publicUrlFor(item) {
  const encoded = encodeURIComponent(objectPathFor(item));
  return `https://firebasestorage.googleapis.com/v0/b/${encodeURIComponent(STORAGE_BUCKET)}/o/${encoded}?alt=media`;
}

/** The Firestore `ProductImageRef` map for one render. */
export function imageRefFor(item) {
  return { path: publicUrlFor(item), source: 'network', altText: item.altText };
}

/** `{ mainImage, galleryMedia }` — the sofa document's final image fields. */
export function sofaImageFields() {
  const ordered = [...SOFA_GALLERY].sort((a, b) => a.order - b.order);
  const main = ordered.find((i) => i.role === 'main');
  return {
    mainImage: imageRefFor(main),
    galleryMedia: ordered.map(imageRefFor),
  };
}

export function sha256Hex(buffer) {
  return createHash('sha256').update(buffer).digest('hex');
}

export function md5Base64(buffer) {
  return createHash('md5').update(buffer).digest('base64');
}

/**
 * Reads + validates one render on disk. Never throws.
 * `{ ok, buffer, sizeBytes, sha256, md5 }` or `{ ok: false, reason }`.
 */
export function preflightSource(workspaceRoot, item) {
  const abs = path.join(workspaceRoot, item.sourceRelPath);
  if (!existsSync(abs)) {
    return { ok: false, reason: `render not found: ${item.sourceRelPath}` };
  }
  const stat = statSync(abs);
  if (!stat.isFile() || stat.size === 0) {
    return { ok: false, reason: `render is not a non-empty file: ${item.sourceRelPath}` };
  }
  if (stat.size > MAX_IMAGE_BYTES) {
    return { ok: false, reason: `render ${stat.size} bytes > ${MAX_IMAGE_BYTES}` };
  }
  const buffer = readFileSync(abs);
  // PNG magic
  if (
    buffer.length < 8 ||
    buffer[0] !== 0x89 ||
    buffer[1] !== 0x50 ||
    buffer[2] !== 0x4e ||
    buffer[3] !== 0x47
  ) {
    return { ok: false, reason: `not a PNG (bad magic): ${item.sourceRelPath}` };
  }
  if (stat.size !== item.expectedSizeBytes) {
    return {
      ok: false,
      reason: `size ${stat.size} != expected ${item.expectedSizeBytes} for ${item.sourceRelPath}`,
    };
  }
  const sha = sha256Hex(buffer);
  if (sha !== item.expectedSha256) {
    return {
      ok: false,
      reason: `SHA-256 mismatch for ${item.sourceRelPath}: expected ${item.expectedSha256}, got ${sha}`,
    };
  }
  return { ok: true, buffer, sizeBytes: stat.size, sha256: sha, md5: md5Base64(buffer) };
}
