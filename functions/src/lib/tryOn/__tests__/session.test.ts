import { describe, expect, it } from "vitest";

import {
  classifyExistingTryOnSession,
  isOwnResultPath,
  timestampToMillis,
  tryOnResultCandidatePaths,
  tryOnResultPath,
  tryOnSessionIdFor,
  tryOnUploadPath,
} from "../session";

describe("tryOnSessionIdFor", () => {
  it("is deterministic for the same (uid, key)", () => {
    expect(tryOnSessionIdFor("alice", "key-1")).toBe(tryOnSessionIdFor("alice", "key-1"));
  });

  it("differs across users for the same key (no cross-user collision)", () => {
    expect(tryOnSessionIdFor("alice", "key-1")).not.toBe(tryOnSessionIdFor("bob", "key-1"));
  });

  it("differs across keys for the same user", () => {
    expect(tryOnSessionIdFor("alice", "key-1")).not.toBe(tryOnSessionIdFor("alice", "key-2"));
  });

  it("is a 64-char lowercase hex string (a valid Firestore + Storage object segment)", () => {
    const id = tryOnSessionIdFor("alice", "key-1");
    expect(id).toMatch(/^[0-9a-f]{64}$/);
  });
});

describe("tryOnUploadPath / tryOnResultPath", () => {
  it("builds the exact owner-scoped Storage paths storage.rules expects", () => {
    const id = tryOnSessionIdFor("alice", "key-1");
    expect(tryOnUploadPath("alice", id)).toBe(`users/alice/tryOnUploads/${id}.jpg`);
    expect(tryOnResultPath("alice", id)).toBe(`users/alice/tryOnResults/${id}.jpg`);
  });

  it("defaults to .jpg but honours an explicit extension for the actual provider output type", () => {
    const id = tryOnSessionIdFor("alice", "key-1");
    expect(tryOnResultPath("alice", id, "jpg")).toBe(`users/alice/tryOnResults/${id}.jpg`);
    expect(tryOnResultPath("alice", id, "png")).toBe(`users/alice/tryOnResults/${id}.png`);
  });
});

describe("tryOnResultCandidatePaths / isOwnResultPath", () => {
  it("lists exactly the two possible result paths for a (uid, sessionId)", () => {
    const id = tryOnSessionIdFor("alice", "key-1");
    expect(tryOnResultCandidatePaths("alice", id)).toEqual([
      `users/alice/tryOnResults/${id}.jpg`,
      `users/alice/tryOnResults/${id}.png`,
    ]);
  });

  it("isOwnResultPath is true for either of this session's own extensions", () => {
    const id = tryOnSessionIdFor("alice", "key-1");
    expect(isOwnResultPath("alice", id, `users/alice/tryOnResults/${id}.jpg`)).toBe(true);
    expect(isOwnResultPath("alice", id, `users/alice/tryOnResults/${id}.png`)).toBe(true);
  });

  it("isOwnResultPath is false for a different session id, a different user, or an arbitrary string", () => {
    const id = tryOnSessionIdFor("alice", "key-1");
    const otherId = tryOnSessionIdFor("alice", "key-2");
    expect(isOwnResultPath("alice", id, `users/alice/tryOnResults/${otherId}.jpg`)).toBe(false);
    expect(isOwnResultPath("alice", id, `users/bob/tryOnResults/${id}.jpg`)).toBe(false);
    expect(isOwnResultPath("alice", id, "https://evil.example.com/x.jpg")).toBe(false);
    expect(isOwnResultPath("alice", id, `users/alice/tryOnResults/${id}.gif`)).toBe(false);
  });
});

describe("timestampToMillis", () => {
  it("reads a Firestore-Timestamp-like object via toMillis()", () => {
    expect(timestampToMillis({ toMillis: () => 12345 })).toBe(12345);
  });

  it("reads a plain {_seconds,_nanoseconds} shape", () => {
    expect(timestampToMillis({ _seconds: 10, _nanoseconds: 500_000_000 })).toBe(10_500);
  });

  it("reads a raw number", () => {
    expect(timestampToMillis(42)).toBe(42);
  });

  it("returns null for anything else", () => {
    expect(timestampToMillis(null)).toBeNull();
    expect(timestampToMillis(undefined)).toBeNull();
    expect(timestampToMillis("not a timestamp")).toBeNull();
    expect(timestampToMillis({})).toBeNull();
  });
});

describe("classifyExistingTryOnSession", () => {
  const NOW = 1_700_000_000_000;
  const STALE_MS = 5 * 60 * 1000;
  const SID = "sess-1";
  const OWN_RESULT_PATH = tryOnResultPath("alice", SID, "jpg");
  const OWN_RESULT_PATH_PNG = tryOnResultPath("alice", SID, "png");

  it("a session owned by another uid -> foreign (hash-collision defence)", () => {
    const v = classifyExistingTryOnSession(
      { userId: "bob", status: "pending" },
      "alice",
      SID,
      NOW,
      STALE_MS,
    );
    expect(v.kind).toBe("foreign");
  });

  it("succeeded with a valid own resultPath + parseable expiresAt -> succeeded, carrying both", () => {
    const v = classifyExistingTryOnSession(
      {
        userId: "alice",
        status: "succeeded",
        resultPath: OWN_RESULT_PATH,
        expiresAt: { toMillis: () => NOW + 60_000 },
      },
      "alice",
      SID,
      NOW,
      STALE_MS,
    );
    expect(v).toEqual({ kind: "succeeded", resultPath: OWN_RESULT_PATH, expiresAtMs: NOW + 60_000 });
  });

  it("succeeded with a valid own .png resultPath is accepted too", () => {
    const v = classifyExistingTryOnSession(
      {
        userId: "alice",
        status: "succeeded",
        resultPath: OWN_RESULT_PATH_PNG,
        expiresAt: { toMillis: () => NOW + 60_000 },
      },
      "alice",
      SID,
      NOW,
      STALE_MS,
    );
    expect(v).toEqual({ kind: "succeeded", resultPath: OWN_RESULT_PATH_PNG, expiresAtMs: NOW + 60_000 });
  });

  it("succeeded with no stored resultPath (already swept) -> attempt_closed, never a guessed path", () => {
    const v = classifyExistingTryOnSession(
      { userId: "alice", status: "succeeded", expiresAt: { toMillis: () => NOW + 60_000 } },
      "alice",
      SID,
      NOW,
      STALE_MS,
    );
    expect(v.kind).toBe("attempt_closed");
  });

  it("succeeded with a FOREIGN resultPath (belongs to another user/session) -> attempt_closed, never trusted or returned", () => {
    const v = classifyExistingTryOnSession(
      {
        userId: "alice",
        status: "succeeded",
        resultPath: "users/bob/tryOnResults/hijack.jpg",
        expiresAt: { toMillis: () => NOW + 60_000 },
      },
      "alice",
      SID,
      NOW,
      STALE_MS,
    );
    expect(v.kind).toBe("attempt_closed");
  });

  it("succeeded with an arbitrary/malformed resultPath string -> attempt_closed", () => {
    const v = classifyExistingTryOnSession(
      {
        userId: "alice",
        status: "succeeded",
        resultPath: "https://evil.example.com/steal.jpg",
        expiresAt: { toMillis: () => NOW + 60_000 },
      },
      "alice",
      SID,
      NOW,
      STALE_MS,
    );
    expect(v.kind).toBe("attempt_closed");
  });

  it("succeeded with a valid resultPath but no parseable expiresAt -> attempt_closed (never a guessed expiry)", () => {
    const v = classifyExistingTryOnSession(
      { userId: "alice", status: "succeeded", resultPath: OWN_RESULT_PATH },
      "alice",
      SID,
      NOW,
      STALE_MS,
    );
    expect(v.kind).toBe("attempt_closed");
  });

  // A cached success must never be handed back once its stated lifetime has
  // ended, even though the D4 TTL sweep (every 30 min) hasn't actually
  // deleted the Storage object yet - fail closed, not "still technically
  // there so still fine".
  it("succeeded but its expiresAt has already passed -> attempt_closed (fail closed, never an expired result)", () => {
    const v = classifyExistingTryOnSession(
      {
        userId: "alice",
        status: "succeeded",
        resultPath: OWN_RESULT_PATH,
        expiresAt: { toMillis: () => NOW - 1 },
      },
      "alice",
      SID,
      NOW,
      STALE_MS,
    );
    expect(v.kind).toBe("attempt_closed");
  });

  it("succeeded exactly AT its expiresAt (boundary, not yet strictly past) -> attempt_closed", () => {
    const v = classifyExistingTryOnSession(
      {
        userId: "alice",
        status: "succeeded",
        resultPath: OWN_RESULT_PATH,
        expiresAt: { toMillis: () => NOW },
      },
      "alice",
      SID,
      NOW,
      STALE_MS,
    );
    expect(v.kind).toBe("attempt_closed");
  });

  it("succeeded one millisecond before its expiresAt -> still succeeded (not yet expired)", () => {
    const v = classifyExistingTryOnSession(
      {
        userId: "alice",
        status: "succeeded",
        resultPath: OWN_RESULT_PATH,
        expiresAt: { toMillis: () => NOW + 1 },
      },
      "alice",
      SID,
      NOW,
      STALE_MS,
    );
    expect(v).toEqual({ kind: "succeeded", resultPath: OWN_RESULT_PATH, expiresAtMs: NOW + 1 });
  });

  it("failed -> attempt_closed", () => {
    const v = classifyExistingTryOnSession({ userId: "alice", status: "failed" }, "alice", SID, NOW, STALE_MS);
    expect(v.kind).toBe("attempt_closed");
  });

  it("expired -> attempt_closed", () => {
    const v = classifyExistingTryOnSession({ userId: "alice", status: "expired" }, "alice", SID, NOW, STALE_MS);
    expect(v.kind).toBe("attempt_closed");
  });

  it("an unknown/corrupt status -> attempt_closed (never resumable)", () => {
    const v = classifyExistingTryOnSession({ userId: "alice", status: "bogus" }, "alice", SID, NOW, STALE_MS);
    expect(v.kind).toBe("attempt_closed");
  });

  it("pending, fresh -> in_progress", () => {
    const v = classifyExistingTryOnSession(
      { userId: "alice", status: "pending", updatedAt: { toMillis: () => NOW - 1000 } },
      "alice",
      SID,
      NOW,
      STALE_MS,
    );
    expect(v.kind).toBe("in_progress");
  });

  it("generating, fresh -> in_progress", () => {
    const v = classifyExistingTryOnSession(
      { userId: "alice", status: "generating", updatedAt: { toMillis: () => NOW - 1000 } },
      "alice",
      SID,
      NOW,
      STALE_MS,
    );
    expect(v.kind).toBe("in_progress");
  });

  it("pending, older than staleMs -> stale (a crashed invocation never wedges the key forever)", () => {
    const v = classifyExistingTryOnSession(
      { userId: "alice", status: "pending", updatedAt: { toMillis: () => NOW - STALE_MS - 1 } },
      "alice",
      SID,
      NOW,
      STALE_MS,
    );
    expect(v.kind).toBe("stale");
  });

  it("pending with no updatedAt falls back to createdAt for staleness", () => {
    const v = classifyExistingTryOnSession(
      { userId: "alice", status: "pending", createdAt: { toMillis: () => NOW - STALE_MS - 1 } },
      "alice",
      SID,
      NOW,
      STALE_MS,
    );
    expect(v.kind).toBe("stale");
  });

  it("pending with neither updatedAt nor createdAt -> treated as in_progress (never guessed stale)", () => {
    const v = classifyExistingTryOnSession({ userId: "alice", status: "pending" }, "alice", SID, NOW, STALE_MS);
    expect(v.kind).toBe("in_progress");
  });
});
