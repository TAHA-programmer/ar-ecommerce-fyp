import type { PushCategory } from "./types";

/**
 * Server-side push-preference evaluation (plan §4.8, D7). The prefs doc is
 * client-writable (rule-validated bools), so the server trusts only an
 * EXPLICIT boolean `false` as "off": a missing doc, missing key, or any
 * non-boolean value means ON (never silently muted by corrupt data). Prefs
 * gate the PUSH only - never the customer inbox write.
 */

export type RawPrefs = Record<string, unknown> | null | undefined;
export type VerifiedRole = "customer" | "superAdmin";

const CUSTOMER_CATEGORIES: readonly PushCategory[] = ["orders", "reviews"];
const ADMIN_CATEGORIES: readonly PushCategory[] = [
  "adminOrders",
  "adminStock",
  "adminModeration",
  "adminPayments",
];

const PREF_KEY: Record<PushCategory, string> = {
  orders: "pushOrders",
  reviews: "pushReviews",
  adminOrders: "pushAdminOrders",
  adminStock: "pushAdminStock",
  adminModeration: "pushAdminModeration",
  adminPayments: "pushAdminPayments",
};

export function prefKeyFor(category: PushCategory): string {
  return PREF_KEY[category];
}

/** Whether the verified role may ever receive `category`. Admin categories
 *  are honoured only for `superAdmin`; a customer who writes `pushAdmin*`
 *  keys gains nothing. */
export function categoryAllowedForRole(category: PushCategory, role: VerifiedRole): boolean {
  if (CUSTOMER_CATEGORIES.includes(category)) return role === "customer";
  if (ADMIN_CATEGORIES.includes(category)) return role === "superAdmin";
  return false;
}

export function isPushEnabledByPrefs(category: PushCategory, prefs: RawPrefs): boolean {
  if (!prefs || typeof prefs !== "object") return true;
  return prefs[PREF_KEY[category]] !== false;
}
