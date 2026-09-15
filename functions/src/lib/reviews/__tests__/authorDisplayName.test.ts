import { describe, expect, it } from "vitest";

import { FALLBACK_REVIEWER_DISPLAY_NAME, maskReviewerDisplayName } from "../authorDisplayName";

describe("maskReviewerDisplayName", () => {
  it("masks a two-part name to \"First L.\"", () => {
    expect(maskReviewerDisplayName("Ayesha Khan")).toBe("Ayesha K.");
  });

  it("masks a name with a middle name using the LAST part's initial", () => {
    expect(maskReviewerDisplayName("Ali Raza Malik")).toBe("Ali M.");
  });

  it("a single-word name is shown as-is", () => {
    expect(maskReviewerDisplayName("Cher")).toBe("Cher");
  });

  it("collapses extra internal whitespace", () => {
    expect(maskReviewerDisplayName("  Ayesha   Khan  ")).toBe("Ayesha K.");
  });

  it("null/undefined fall back to the safe default", () => {
    expect(maskReviewerDisplayName(null)).toBe(FALLBACK_REVIEWER_DISPLAY_NAME);
    expect(maskReviewerDisplayName(undefined)).toBe(FALLBACK_REVIEWER_DISPLAY_NAME);
  });

  it("empty/whitespace-only falls back to the safe default", () => {
    expect(maskReviewerDisplayName("")).toBe(FALLBACK_REVIEWER_DISPLAY_NAME);
    expect(maskReviewerDisplayName("   ")).toBe(FALLBACK_REVIEWER_DISPLAY_NAME);
  });

  it("never reveals more than a first name + one initial", () => {
    const masked = maskReviewerDisplayName("Fatima Zahra Bibi Sultana");
    expect(masked).toBe("Fatima S.");
    expect(masked).not.toContain("Zahra");
    expect(masked).not.toContain("Bibi");
  });
});
