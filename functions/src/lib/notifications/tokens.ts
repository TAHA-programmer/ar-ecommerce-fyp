import { createHash } from "crypto";

import { DEVICE_TOKEN_TTL_MS, MAX_DEVICES_PER_USER } from "./constants";
import type { VerifiedRole } from "./prefs";

/**
 * Pure helpers for device-token registration (plan §4.7). The callables that
 * use them are Stage S3; S1 only defines and tests the pure parts.
 */

export class DeviceRegistrationValidationError extends Error {}

export interface RegisterDeviceRequest {
  token: string;
  platform: "android";
  appVersion: string;
  installId: string;
}

const TOKEN_SHAPE = /^[A-Za-z0-9_\-:.]+$/;
const TOKEN_MIN = 100;
const TOKEN_MAX = 4096;
const APP_VERSION_MAX = 32;
const INSTALL_ID_MAX = 64;
const SAFE_META = /^[A-Za-z0-9_.+\- ]*$/;

function asRecord(data: unknown): Record<string, unknown> {
  if (!data || typeof data !== "object" || Array.isArray(data)) {
    throw new DeviceRegistrationValidationError("request must be an object");
  }
  return data as Record<string, unknown>;
}

/** Strict shape validation of a `registerDevice` payload. Unknown keys are
 *  ignored (never copied); nothing the client sends can set `role`, `uid`
 *  or timestamps. */
export function parseRegisterDeviceRequest(data: unknown): RegisterDeviceRequest {
  const d = asRecord(data);

  const token = d.token;
  if (
    typeof token !== "string" ||
    token.length < TOKEN_MIN ||
    token.length > TOKEN_MAX ||
    !TOKEN_SHAPE.test(token)
  ) {
    throw new DeviceRegistrationValidationError("invalid token");
  }

  if (d.platform !== "android") {
    throw new DeviceRegistrationValidationError("invalid platform");
  }

  const appVersion = d.appVersion;
  if (
    typeof appVersion !== "string" ||
    appVersion.length === 0 ||
    appVersion.length > APP_VERSION_MAX ||
    !SAFE_META.test(appVersion)
  ) {
    throw new DeviceRegistrationValidationError("invalid appVersion");
  }

  const installId = d.installId;
  if (
    typeof installId !== "string" ||
    installId.length === 0 ||
    installId.length > INSTALL_ID_MAX ||
    !SAFE_META.test(installId)
  ) {
    throw new DeviceRegistrationValidationError("invalid installId");
  }

  return { token, platform: "android", appVersion, installId };
}

/** `unregisterDevice` payload: just the token (same shape rule). */
export function parseUnregisterDeviceRequest(data: unknown): { token: string } {
  const d = asRecord(data);
  const token = d.token;
  if (
    typeof token !== "string" ||
    token.length < TOKEN_MIN ||
    token.length > TOKEN_MAX ||
    !TOKEN_SHAPE.test(token)
  ) {
    throw new DeviceRegistrationValidationError("invalid token");
  }
  return { token };
}

/** `deviceTokens/{sha256(token)}` - the token never appears in a doc id or a
 *  log line; ownership moves by overwriting this one document. */
export function deviceTokenDocId(token: string): string {
  return createHash("sha256").update(token, "utf8").digest("hex");
}

/** Role from the VERIFIED ID-token claim only (`request.auth.token.role`),
 *  mirroring `firestore.rules#isAdmin()`. Anything else is a customer. */
export function roleFromClaim(claimRole: unknown): VerifiedRole {
  return claimRole === "superAdmin" ? "superAdmin" : "customer";
}

export interface DeviceSummary {
  id: string;
  lastSeenMs: number;
}

/** Which of a user's devices to delete so at most `cap` remain, oldest
 *  `lastSeenAt` first. `keepId` (the device being registered right now) is
 *  never evicted. Ties break by id for determinism. */
export function selectDevicesToEvict(
  devices: readonly DeviceSummary[],
  keepId: string,
  cap: number = MAX_DEVICES_PER_USER,
): string[] {
  const others = devices.filter((d) => d.id !== keepId);
  const total = others.length + 1; // the kept/new device always counts
  const excess = total - cap;
  if (excess <= 0) return [];
  return [...others]
    .sort((a, b) => a.lastSeenMs - b.lastSeenMs || (a.id < b.id ? -1 : a.id > b.id ? 1 : 0))
    .slice(0, excess)
    .map((d) => d.id);
}

export function deviceTokenExpireAtMs(nowMs: number): number {
  return nowMs + DEVICE_TOKEN_TTL_MS;
}
