import { defineConfig } from "vitest/config";

// Pure unit tests only - no emulator, no network. Run with `npm test`.
export default defineConfig({
  test: {
    include: ["src/**/*.test.ts"],
    environment: "node",
  },
});
