import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    include: ["flows/**/*.test.ts"],
    testTimeout: 120_000,
    hookTimeout: 60_000,
    fileParallel: false,
    pool: "forks",
    poolOptions: {
      forks: {
        singleFork: true,
      },
    },
  },
});
