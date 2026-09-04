import { defineConfig } from "vitest/config";

// Integration tests that run `createPaymentIntent` against the real Firestore
// emulator (Admin SDK), with a MOCK Stripe boundary - no live/sandbox Stripe
// call. Run via `npm run test:emulator`, which wraps this in
// `firebase emulators:exec --only firestore`.
export default defineConfig({
  test: {
    include: ["test/**/*.test.ts"],
    environment: "node",
    // All emulator tests share one Firestore instance and clear it between
    // cases - they must not run in parallel.
    fileParallelism: false,
    sequence: { concurrent: false },
    testTimeout: 30_000,
    hookTimeout: 30_000,
  },
});
