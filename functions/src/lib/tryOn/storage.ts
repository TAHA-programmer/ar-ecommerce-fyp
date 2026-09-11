import { getStorage } from "firebase-admin/storage";
import * as logger from "firebase-functions/logger";

/**
 * Narrow Admin Storage helpers for the Virtual Try-On path (Phase 9.3
 * Stage 4). Every path passed in is ALREADY the exact, owner/product-scoped
 * object path resolved by `eligibility.ts` / `session.ts` - never a raw
 * client-supplied string - so there is no path-traversal surface here.
 */

function bucket() {
  return getStorage().bucket();
}

export interface StoredObject {
  bytes: Buffer;
  contentType: string;
  size: number;
}

/** `null` when the object does not exist - the caller decides how to fail. */
export async function readObjectBytes(path: string): Promise<StoredObject | null> {
  const file = bucket().file(path);
  const [exists] = await file.exists();
  if (!exists) return null;
  const [meta, bytes] = await Promise.all([file.getMetadata(), file.download()]);
  const [data] = bytes;
  const contentType =
    typeof meta[0]?.contentType === "string" ? meta[0].contentType : "application/octet-stream";
  return { bytes: data, contentType, size: data.length };
}

export async function writeObjectBytes(
  path: string,
  bytes: Buffer,
  contentType: string,
): Promise<void> {
  await bucket().file(path).save(bytes, {
    contentType,
    resumable: false,
    metadata: { contentType, cacheControl: "private, max-age=0, no-store" },
  });
}

/** Best-effort delete - never throws. Returns `true` iff the object was
 *  (or already was not) present afterwards. Logged on failure so a repeated
 *  cleanup failure is diagnosable without ever leaking the path contents. */
export async function deleteObjectBestEffort(path: string, context: string): Promise<boolean> {
  try {
    await bucket().file(path).delete({ ignoreNotFound: true });
    return true;
  } catch (err) {
    logger.warn(`${context}: best-effort Storage delete failed`, {
      name: (err as { name?: unknown })?.name,
      code: (err as { code?: unknown })?.code,
    });
    return false;
  }
}

/** Delete every object under a Storage prefix (best-effort, bounded pages).
 *  Used by the user-deletion cleanup trigger to catch any stray object a
 *  per-session delete might have missed. */
export async function deletePrefixBestEffort(prefix: string, context: string): Promise<number> {
  try {
    const [files] = await bucket().getFiles({ prefix });
    if (files.length === 0) return 0;
    await Promise.all(files.map((f) => f.delete({ ignoreNotFound: true })));
    return files.length;
  } catch (err) {
    logger.warn(`${context}: best-effort prefix delete failed`, {
      prefix,
      name: (err as { name?: unknown })?.name,
    });
    return 0;
  }
}

function objectCreatedAtMs(metadata: Record<string, unknown> | undefined): number | null {
  const raw = metadata?.timeCreated;
  if (typeof raw !== "string") return null;
  const ms = Date.parse(raw);
  return Number.isFinite(ms) ? ms : null;
}

/**
 * List objects under `prefix` whose object name contains `pathSegment` and
 * whose `timeCreated` is older than `olderThanMs` relative to `nowMs`.
 * Bounded to `maxFiles` inspected objects per call. An object whose creation
 * time cannot be determined is skipped (never guessed as stale) - never
 * throws; a listing failure returns an empty list and logs a warning.
 *
 * Used by the orphan-upload recovery sweep: `generateTryOn` deletes a
 * person-photo upload unconditionally the moment it runs at all, so one that
 * survives this long can only be a genuine orphan (never called, or the one
 * invocation that would have deleted it crashed before it got the chance).
 */
export async function listStaleObjectsUnderPrefix(args: {
  prefix: string;
  pathSegment: string;
  nowMs: number;
  olderThanMs: number;
  maxFiles: number;
}): Promise<string[]> {
  try {
    const [files] = await bucket().getFiles({ prefix: args.prefix, maxResults: args.maxFiles });
    const stale: string[] = [];
    for (const f of files) {
      if (!f.name.includes(args.pathSegment)) continue;
      const createdMs = objectCreatedAtMs(f.metadata as Record<string, unknown> | undefined);
      if (createdMs === null) continue;
      if (args.nowMs - createdMs >= args.olderThanMs) {
        stale.push(f.name);
      }
    }
    return stale;
  } catch (err) {
    logger.warn("listStaleObjectsUnderPrefix: listing failed - skipping this run", {
      prefix: args.prefix,
      name: (err as { name?: unknown })?.name,
    });
    return [];
  }
}
