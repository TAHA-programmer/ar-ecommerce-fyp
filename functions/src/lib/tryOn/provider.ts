import * as logger from "firebase-functions/logger";

import { VTO_GEMINI_ENDPOINT, VTO_PROVIDER_TIMEOUT_MS } from "../../config";

/**
 * The Virtual Try-On image-generation provider seam (Phase 9.3 Stage 4).
 *
 * `generateTryOn` depends only on the {@link VtoProvider} interface, never on
 * Gemini directly - the tracker's D2 decision is LOCKED to
 * `gemini-2.5-flash-image`, but keeping this seam means a later switch to
 * Vertex AI Virtual Try-On (§7 option B, documented as the drop-in upgrade
 * if quality complaints arise) is a one-file change, not a rewrite.
 *
 * Every automated test injects a fake {@link VtoProvider} (unit) or a fake
 * `fetchImpl` (provider-module tests) - this pass makes ZERO real network
 * calls to Gemini or any other provider.
 */

export interface VtoGenerateInput {
  personBytes: Buffer;
  personContentType: string;
  garmentBytes: Buffer;
  garmentContentType: string;
  /** One of `ProductVtoMetadata.supportedGarmentCategories` - a styling hint only. */
  garmentCategory: string;
  /** A catalogue size, e.g. `"L"` - a soft styling hint only, NEVER a fit input (§8). */
  sizeHint: string | null;
}

export interface VtoGenerateResult {
  imageBytes: Buffer;
  contentType: string;
}

export type VtoProviderErrorKind = "network" | "auth" | "safety_block" | "bad_response" | "timeout";

export class VtoProviderError extends Error {
  readonly kind: VtoProviderErrorKind;
  readonly httpStatus?: number;

  constructor(kind: VtoProviderErrorKind, message: string, httpStatus?: number) {
    super(message);
    this.name = "VtoProviderError";
    this.kind = kind;
    this.httpStatus = httpStatus;
  }
}

export interface VtoProvider {
  readonly name: string;
  generate(input: VtoGenerateInput): Promise<VtoGenerateResult>;
}

/**
 * The honest, SRS-compliant instruction: change ONLY the garment, preserve
 * the person's identity/pose/background, and NEVER treat the size as a fit
 * computation (§8 - "no fit calculator, no measurement inputs"). Developer
 * decision D2 already accepts that Gemini may still reframe/crop or drift
 * identity/hair somewhat despite this instruction - that trade-off is
 * disclosed to the customer in the UI (Stage 5), not hidden here.
 */
export function buildTryOnPrompt(garmentCategory: string, sizeHint: string | null): string {
  const sizePhrase = sizeHint
    ? ` The garment may be styled as if it were size ${sizeHint}, but do not change the person's body shape, proportions, or measurements.`
    : "";
  return (
    "You are given two images. The first image shows a person. The second image shows a single " +
    `${garmentCategory} garment by itself. Generate a new photo of the SAME person wearing the ` +
    `garment from the second image, replacing only the ${garmentCategory} they are currently ` +
    "wearing. Keep the person's face, hair, skin tone, body shape, pose, and the original " +
    `background exactly as in the first image. Do not add, remove, or alter any other clothing ` +
    `or accessories.${sizePhrase} This is a visual style preview only - it is not a fit, size, ` +
    "or measurement recommendation."
  );
}

type FetchLike = typeof fetch;

interface GeminiInlinePart {
  inlineData?: { mimeType?: string; data?: string };
  text?: string;
}
interface GeminiCandidate {
  content?: { parts?: GeminiInlinePart[] };
  finishReason?: string;
}
interface GeminiResponseBody {
  candidates?: GeminiCandidate[];
  promptFeedback?: { blockReason?: string };
}

const SAFETY_FINISH_REASONS = new Set([
  "SAFETY",
  "PROHIBITED_CONTENT",
  "BLOCKLIST",
  "SPII",
  "IMAGE_SAFETY",
]);

function parseGeminiResponse(body: GeminiResponseBody): VtoGenerateResult {
  if (body.promptFeedback?.blockReason) {
    throw new VtoProviderError("safety_block", `blocked: ${body.promptFeedback.blockReason}`);
  }
  const candidate = body.candidates?.[0];
  if (candidate?.finishReason && SAFETY_FINISH_REASONS.has(candidate.finishReason)) {
    throw new VtoProviderError("safety_block", `finishReason: ${candidate.finishReason}`);
  }
  const parts = candidate?.content?.parts ?? [];
  for (const part of parts) {
    if (part.inlineData?.data) {
      return {
        imageBytes: Buffer.from(part.inlineData.data, "base64"),
        contentType: part.inlineData.mimeType || "image/png",
      };
    }
  }
  throw new VtoProviderError("bad_response", "no image returned by the provider");
}

/**
 * Gemini Developer API `generateContent` REST call - plain `fetch`, no SDK
 * (matches the tracker's §9.1 design note). The API key is sent as the
 * `x-goog-api-key` header, never a query parameter, so it can never leak
 * into a logged URL. NO retry anywhere in this function - a failed or timed
 * out call is surfaced to the caller as-is (D9 / UC-15 4B: never a second
 * billable attempt from inside this path).
 *
 * `fetchImpl` is an injectable seam purely for testing - production always
 * uses the global `fetch` default, and no automated test ever exercises the
 * real network path.
 */
export function geminiProvider(apiKey: string, fetchImpl: FetchLike = fetch): VtoProvider {
  return {
    name: "gemini",
    async generate(input: VtoGenerateInput): Promise<VtoGenerateResult> {
      const controller = new AbortController();
      const timeout = setTimeout(() => controller.abort(), VTO_PROVIDER_TIMEOUT_MS);

      const body = {
        contents: [
          {
            parts: [
              { text: buildTryOnPrompt(input.garmentCategory, input.sizeHint) },
              {
                inlineData: {
                  mimeType: input.personContentType,
                  data: input.personBytes.toString("base64"),
                },
              },
              {
                inlineData: {
                  mimeType: input.garmentContentType,
                  data: input.garmentBytes.toString("base64"),
                },
              },
            ],
          },
        ],
        generationConfig: { responseModalities: ["IMAGE"] },
      };

      let res: Response;
      try {
        res = await fetchImpl(VTO_GEMINI_ENDPOINT, {
          method: "POST",
          headers: { "Content-Type": "application/json", "x-goog-api-key": apiKey },
          body: JSON.stringify(body),
          signal: controller.signal,
        });
      } catch (err) {
        if ((err as { name?: string })?.name === "AbortError") {
          throw new VtoProviderError("timeout", "Gemini request timed out");
        }
        throw new VtoProviderError("network", "Gemini request failed to send");
      } finally {
        clearTimeout(timeout);
      }

      if (res.status === 401 || res.status === 403) {
        // The bound GEMINI_API_KEY is wrong/rotated/unset. Operational, not
        // the customer's problem - never leak this detail to the client.
        logger.error("generateTryOn: Gemini authentication failed - GEMINI_API_KEY may be misconfigured");
        throw new VtoProviderError("auth", "Gemini authentication failed", res.status);
      }
      if (!res.ok) {
        logger.error("generateTryOn: Gemini call failed", { status: res.status });
        throw new VtoProviderError("network", `Gemini returned HTTP ${res.status}`, res.status);
      }

      let json: GeminiResponseBody;
      try {
        json = (await res.json()) as GeminiResponseBody;
      } catch {
        throw new VtoProviderError("bad_response", "Gemini returned a non-JSON response");
      }
      return parseGeminiResponse(json);
    },
  };
}

/**
 * §7 option B - the purpose-built, SRS-named provider. NOT selected (D2:
 * cost priority), but the seam is documented so a future switch to
 * `virtual-try-on-001` is a one-file change: implement this function the
 * same way as {@link geminiProvider} (REST `:predict` call, ADC / a
 * service-account credential from Secret Manager) and swap the binding in
 * `generateTryOn.ts`. Intentionally throws if ever invoked - there is no
 * Vertex credential wired up in this Stage.
 */
export function vertexProviderStub(): VtoProvider {
  return {
    name: "vertex",
    async generate(): Promise<VtoGenerateResult> {
      throw new VtoProviderError(
        "bad_response",
        "Vertex AI Virtual Try-On is not implemented - Gemini is the locked provider (D2)",
      );
    },
  };
}
