import { describe, it, expect } from "vitest";

import { buildDeliveryAddressSnapshot } from "../address";

const completeAddress = {
  label: "Home",
  fullName: "Alice Khan",
  phoneNumber: "03001234567",
  addressLine1: "1 Test Road",
  addressLine2: null,
  city: "Karachi",
  provinceOrState: "Sindh",
  postalCode: "74000",
  createdAt: { toMillis: () => 0 },
};

describe("buildDeliveryAddressSnapshot", () => {
  it("produces exactly the 10 order-compatible keys with nullables as null", () => {
    const snap = buildDeliveryAddressSnapshot("addr_1", completeAddress, "addr_1");
    expect(Object.keys(snap).sort()).toEqual(
      [
        "id",
        "label",
        "fullName",
        "phoneNumber",
        "addressLine1",
        "addressLine2",
        "city",
        "provinceOrState",
        "postalCode",
        "isDefault",
      ].sort(),
    );
    expect(snap.id).toBe("addr_1");
    expect(snap.addressLine2).toBeNull();
    expect(snap.isDefault).toBe(true);
  });

  it("derives isDefault from the pointer, not a stored field", () => {
    expect(buildDeliveryAddressSnapshot("addr_1", completeAddress, "addr_2").isDefault).toBe(false);
    expect(buildDeliveryAddressSnapshot("addr_1", completeAddress, null).isDefault).toBe(false);
  });

  it("coerces a missing optional label to null and keeps a present one", () => {
    expect(
      buildDeliveryAddressSnapshot("a", { ...completeAddress, label: undefined }, null).label,
    ).toBeNull();
    expect(buildDeliveryAddressSnapshot("a", completeAddress, null).label).toBe("Home");
  });

  it("throws ADDRESS_INCOMPLETE when a rules-required field is empty", () => {
    for (const field of [
      "fullName",
      "phoneNumber",
      "addressLine1",
      "city",
      "provinceOrState",
      "postalCode",
    ]) {
      expect(() =>
        buildDeliveryAddressSnapshot("a", { ...completeAddress, [field]: "" }, null),
      ).toThrow();
      expect(() =>
        buildDeliveryAddressSnapshot("a", { ...completeAddress, [field]: "   " }, null),
      ).toThrow();
    }
  });
});
