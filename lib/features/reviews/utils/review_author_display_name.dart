/// Safe customer display name for a review's author (Ratings/Reviews v1 §0
/// decision 13: "Display only a safe customer display name — never email or
/// phone", §6: "a masked display name resolved through whatever
/// `UserProfileRepository` already exposes... reuse, do not invent a new
/// identity field").
///
/// Shown for EVERY review, including a `hidden`/blank `UserProfileModel
/// .displayName` (a deleted profile, a not-yet-onboarded legacy account, or
/// simply a lookup failure) - this never surfaces raw account data and never
/// leaves a review with a blank/null author.
const String kFallbackReviewerDisplayName = 'Verified Buyer';

/// Masks a full profile display name down to "First L." (first name plus
/// the last name's initial) - e.g. "Ayesha Khan" -> "Ayesha K.". A
/// single-word name is shown as-is ("Ayesha" -> "Ayesha"); a blank/missing
/// name falls back to [kFallbackReviewerDisplayName].
String maskReviewerDisplayName(String? rawDisplayName) {
  final trimmed = (rawDisplayName ?? '').trim();
  if (trimmed.isEmpty) return kFallbackReviewerDisplayName;

  final parts = trimmed
      .split(RegExp(r'\s+'))
      .where((p) => p.isNotEmpty)
      .toList();
  if (parts.length == 1) return parts.first;

  final first = parts.first;
  final lastInitial = parts.last.substring(0, 1).toUpperCase();
  return '$first $lastInitial.';
}
