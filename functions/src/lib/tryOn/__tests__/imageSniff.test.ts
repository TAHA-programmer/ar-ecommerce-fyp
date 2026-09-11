import { describe, expect, it } from "vitest";

import { bytesMatchDeclaredType, extensionForContentType, sniffImageContentType } from "../imageSniff";

const JPEG_BYTES = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3, 4]);
const PNG_BYTES = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 1, 2]);
const GARBAGE_BYTES = Buffer.from("not an image at all");
const TRUNCATED_PNG = Buffer.from([0x89, 0x50, 0x4e]);

describe("sniffImageContentType", () => {
  it("recognises a real JPEG signature", () => {
    expect(sniffImageContentType(JPEG_BYTES)).toBe("image/jpeg");
  });

  it("recognises a real PNG signature", () => {
    expect(sniffImageContentType(PNG_BYTES)).toBe("image/png");
  });

  it("returns null for arbitrary non-image bytes", () => {
    expect(sniffImageContentType(GARBAGE_BYTES)).toBeNull();
  });

  it("returns null for empty bytes", () => {
    expect(sniffImageContentType(Buffer.alloc(0))).toBeNull();
  });

  it("returns null for bytes too short to carry a full signature", () => {
    expect(sniffImageContentType(TRUNCATED_PNG)).toBeNull();
  });

  it("does not misclassify a GLB (Room AR model) as an image", () => {
    // glTF binary magic: 'glTF' + version
    expect(sniffImageContentType(Buffer.from([0x67, 0x6c, 0x54, 0x46, 2, 0, 0, 0]))).toBeNull();
  });
});

describe("bytesMatchDeclaredType", () => {
  it("true when the real signature matches the declared type", () => {
    expect(bytesMatchDeclaredType(JPEG_BYTES, "image/jpeg")).toBe(true);
    expect(bytesMatchDeclaredType(PNG_BYTES, "image/png")).toBe(true);
  });

  it("false when the declared type does not match the real signature (spoofed content-type)", () => {
    expect(bytesMatchDeclaredType(JPEG_BYTES, "image/png")).toBe(false);
    expect(bytesMatchDeclaredType(PNG_BYTES, "image/jpeg")).toBe(false);
  });

  it("false for non-image bytes declared as an image", () => {
    expect(bytesMatchDeclaredType(GARBAGE_BYTES, "image/jpeg")).toBe(false);
  });
});

describe("extensionForContentType", () => {
  it("maps the two supported types to their extensions", () => {
    expect(extensionForContentType("image/jpeg")).toBe("jpg");
    expect(extensionForContentType("image/png")).toBe("png");
  });

  it("returns null for an unsupported type", () => {
    expect(extensionForContentType("image/webp")).toBeNull();
    expect(extensionForContentType("application/octet-stream")).toBeNull();
  });
});
