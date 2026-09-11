import { describe, expect, it, vi } from "vitest";

import { buildTryOnPrompt, geminiProvider, VtoProviderError } from "../provider";

const INPUT = {
  personBytes: Buffer.from("person-bytes"),
  personContentType: "image/jpeg",
  garmentBytes: Buffer.from("garment-bytes"),
  garmentContentType: "image/png",
  garmentCategory: "top",
  sizeHint: "L" as string | null,
};

function fakeResponse(overrides: {
  ok?: boolean;
  status?: number;
  json?: () => Promise<unknown>;
}) {
  return {
    ok: overrides.ok ?? true,
    status: overrides.status ?? 200,
    json: overrides.json ?? (async () => ({})),
  } as unknown as Response;
}

describe("buildTryOnPrompt", () => {
  it("names the exact garment category and instructs identity/background preservation", () => {
    const prompt = buildTryOnPrompt("dress", null);
    expect(prompt).toContain("dress");
    expect(prompt.toLowerCase()).toContain("keep the person's face");
  });

  it("includes the size only as a soft styling hint, never a fit/measurement claim", () => {
    const withSize = buildTryOnPrompt("top", "M");
    expect(withSize).toContain("size M");
    expect(withSize.toLowerCase()).toContain("not change the person's body shape");
    const withoutSize = buildTryOnPrompt("top", null);
    expect(withoutSize).not.toContain("size ");
  });

  it("always states this is a visual preview, never a fit/size recommendation (SRS honesty requirement)", () => {
    expect(buildTryOnPrompt("top", "L").toLowerCase()).toContain("not a fit, size, or measurement");
  });
});

describe("geminiProvider - request shape", () => {
  it("sends the API key as a header, never in the URL, and base64-encodes both images", async () => {
    const fetchImpl = vi.fn(async (url: unknown, init: unknown) => {
      const u = url as string;
      expect(u).not.toContain("secret-key");
      const req = init as { headers: Record<string, string>; body: string };
      expect(req.headers["x-goog-api-key"]).toBe("secret-key");
      const body = JSON.parse(req.body);
      const parts = body.contents[0].parts;
      expect(parts[1].inlineData.data).toBe(INPUT.personBytes.toString("base64"));
      expect(parts[1].inlineData.mimeType).toBe("image/jpeg");
      expect(parts[2].inlineData.data).toBe(INPUT.garmentBytes.toString("base64"));
      return fakeResponse({
        json: async () => ({
          candidates: [
            { content: { parts: [{ inlineData: { mimeType: "image/png", data: "aW1nYnl0ZXM=" } }] } },
          ],
        }),
      });
    });

    const provider = geminiProvider("secret-key", fetchImpl as unknown as typeof fetch);
    const result = await provider.generate(INPUT);
    expect(result.contentType).toBe("image/png");
    expect(result.imageBytes.toString()).toBe("imgbytes");
    expect(fetchImpl).toHaveBeenCalledTimes(1);
  });
});

describe("geminiProvider - success parsing", () => {
  it("returns the first inlineData part's bytes + mimeType", async () => {
    const fetchImpl = async () =>
      fakeResponse({
        json: async () => ({
          candidates: [
            {
              content: {
                parts: [
                  { text: "here is the result" },
                  { inlineData: { mimeType: "image/png", data: Buffer.from("hi").toString("base64") } },
                ],
              },
            },
          ],
        }),
      });
    const provider = geminiProvider("key", fetchImpl as unknown as typeof fetch);
    const result = await provider.generate(INPUT);
    expect(result.imageBytes.toString()).toBe("hi");
    expect(result.contentType).toBe("image/png");
  });

  it("defaults contentType to image/png when the provider omits mimeType", async () => {
    const fetchImpl = async () =>
      fakeResponse({
        json: async () => ({
          candidates: [{ content: { parts: [{ inlineData: { data: "aGk=" } }] } }],
        }),
      });
    const provider = geminiProvider("key", fetchImpl as unknown as typeof fetch);
    const result = await provider.generate(INPUT);
    expect(result.contentType).toBe("image/png");
  });
});

describe("geminiProvider - failure mapping", () => {
  it("maps a promptFeedback.blockReason to safety_block", async () => {
    const fetchImpl = async () =>
      fakeResponse({ json: async () => ({ promptFeedback: { blockReason: "SAFETY" } }) });
    const provider = geminiProvider("key", fetchImpl as unknown as typeof fetch);
    await expect(provider.generate(INPUT)).rejects.toMatchObject({ kind: "safety_block" });
  });

  it("maps a candidate finishReason of SAFETY to safety_block", async () => {
    const fetchImpl = async () =>
      fakeResponse({ json: async () => ({ candidates: [{ finishReason: "SAFETY", content: {} }] }) });
    const provider = geminiProvider("key", fetchImpl as unknown as typeof fetch);
    await expect(provider.generate(INPUT)).rejects.toMatchObject({ kind: "safety_block" });
  });

  it("maps no candidates / no image part to bad_response", async () => {
    const fetchImpl = async () => fakeResponse({ json: async () => ({}) });
    const provider = geminiProvider("key", fetchImpl as unknown as typeof fetch);
    await expect(provider.generate(INPUT)).rejects.toMatchObject({ kind: "bad_response" });
  });

  it("maps a text-only response (no inlineData) to bad_response", async () => {
    const fetchImpl = async () =>
      fakeResponse({ json: async () => ({ candidates: [{ content: { parts: [{ text: "sorry" }] } }] }) });
    const provider = geminiProvider("key", fetchImpl as unknown as typeof fetch);
    await expect(provider.generate(INPUT)).rejects.toMatchObject({ kind: "bad_response" });
  });

  it("maps HTTP 401/403 to auth (never exposed to the customer as a distinct message)", async () => {
    const fetchImpl = async () => fakeResponse({ ok: false, status: 401 });
    const provider = geminiProvider("key", fetchImpl as unknown as typeof fetch);
    await expect(provider.generate(INPUT)).rejects.toMatchObject({ kind: "auth" });
  });

  it("maps a generic non-2xx status to network", async () => {
    const fetchImpl = async () => fakeResponse({ ok: false, status: 503 });
    const provider = geminiProvider("key", fetchImpl as unknown as typeof fetch);
    await expect(provider.generate(INPUT)).rejects.toMatchObject({ kind: "network" });
  });

  it("maps a non-JSON response body to bad_response", async () => {
    const fetchImpl = async () =>
      fakeResponse({
        json: async () => {
          throw new Error("not json");
        },
      });
    const provider = geminiProvider("key", fetchImpl as unknown as typeof fetch);
    await expect(provider.generate(INPUT)).rejects.toMatchObject({ kind: "bad_response" });
  });

  it("maps an aborted (timed-out) fetch to timeout, never retrying", async () => {
    const fetchImpl = vi.fn(async () => {
      const e = new Error("aborted");
      e.name = "AbortError";
      throw e;
    });
    const provider = geminiProvider("key", fetchImpl as unknown as typeof fetch);
    await expect(provider.generate(INPUT)).rejects.toMatchObject({ kind: "timeout" });
    expect(fetchImpl).toHaveBeenCalledTimes(1); // no retry
  });

  it("maps a raw network throw to network, never retrying", async () => {
    const fetchImpl = vi.fn(async () => {
      throw new Error("ECONNRESET");
    });
    const provider = geminiProvider("key", fetchImpl as unknown as typeof fetch);
    await expect(provider.generate(INPUT)).rejects.toMatchObject({ kind: "network" });
    expect(fetchImpl).toHaveBeenCalledTimes(1);
  });

  it("every rejection is a VtoProviderError instance", async () => {
    const fetchImpl = async () => fakeResponse({ ok: false, status: 500 });
    const provider = geminiProvider("key", fetchImpl as unknown as typeof fetch);
    try {
      await provider.generate(INPUT);
      throw new Error("expected a throw");
    } catch (err) {
      expect(err).toBeInstanceOf(VtoProviderError);
    }
  });
});
