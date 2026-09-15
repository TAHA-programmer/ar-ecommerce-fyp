/**
 * Server-side mirror of `lib/features/reviews/utils/review_author_display_name.dart`
 * - kept byte-for-byte equivalent in behaviour so the client's own copy
 * (used only for its own already-resolved `ReviewModel.authorDisplayName`,
 * never to recompute one) can never silently drift from what the server
 * actually stamps onto a review document.
 *
 * This is the ONLY place a customer's real profile `displayName` is ever
 * read in order to show it to ANOTHER customer (Ratings/Reviews v1 §0
 * decision 13 / §6) - `submitReview` calls this once, server-side (Admin
 * SDK, bypasses `firestore.rules`' owner/admin-only `users/{uid}` read
 * rule), and stores ONLY the already-masked result on the review document.
 * No client - including this app's own client code - EVER reads another
 * customer's raw `users/{uid}` document to resolve a review author's name;
 * that path is not just discouraged, it is impossible under the deployed
 * rules.
 */

export const FALLBACK_REVIEWER_DISPLAY_NAME = "Verified Buyer";

/** Masks a full profile display name down to "First L." (first name plus
 * the last name's initial) - e.g. "Ayesha Khan" -> "Ayesha K.". A
 * single-word name is shown as-is; a blank/missing name falls back to
 * {@link FALLBACK_REVIEWER_DISPLAY_NAME}. */
export function maskReviewerDisplayName(
  rawDisplayName: string | null | undefined,
): string {
  const trimmed = (rawDisplayName ?? "").trim();
  if (trimmed.length === 0) return FALLBACK_REVIEWER_DISPLAY_NAME;

  const parts = trimmed.split(/\s+/).filter((p) => p.length > 0);
  if (parts.length === 1) return parts[0];

  const first = parts[0];
  const lastInitial = parts[parts.length - 1].charAt(0).toUpperCase();
  return `${first} ${lastInitial}.`;
}
