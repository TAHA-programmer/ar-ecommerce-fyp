import { readFileSync } from "fs";
import { join } from "path";
import { describe, expect, it } from "vitest";

import {
  DEVICE_TOKEN_TTL_MS,
  FCM_MESSAGE_TTL_MS,
  INBOX_TTL_MS,
  LEDGER_TTL_MS,
  LOW_STOCK_THRESHOLD,
  MAX_DEVICES_PER_USER,
} from "..";

describe("constants", () => {
  it("LOW_STOCK_THRESHOLD matches the Flutter client's CommerceDatabase.lowStockThreshold", () => {
    const dartPath = join(__dirname, "../../../../../lib/core/data/commerce_database.dart");
    const src = readFileSync(dartPath, "utf8");
    const m = /static const int lowStockThreshold\s*=\s*(\d+)\s*;/.exec(src);
    expect(m, "could not find lowStockThreshold in commerce_database.dart").not.toBeNull();
    expect(LOW_STOCK_THRESHOLD).toBe(Number(m![1]));
  });

  it("retention values follow the plan (90d inbox, 60d tokens, 7d ledger, 24h fcm ttl, 10 devices)", () => {
    const day = 24 * 60 * 60 * 1000;
    expect(INBOX_TTL_MS).toBe(90 * day);
    expect(DEVICE_TOKEN_TTL_MS).toBe(60 * day);
    expect(LEDGER_TTL_MS).toBe(7 * day);
    expect(FCM_MESSAGE_TTL_MS).toBe(day);
    expect(MAX_DEVICES_PER_USER).toBe(10);
  });
});
