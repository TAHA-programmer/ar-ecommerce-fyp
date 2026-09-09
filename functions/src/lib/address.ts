import { errAddressIncomplete } from "./errors";

/**
 * Build the delivery-address snapshot embedded in a checkout session (and,
 * in Phase 8.13.3, copied verbatim into `orders/{id}.deliveryAddress`).
 *
 * The shape is EXACTLY the 10 keys `firestore.rules`' `isValidDeliveryAddress`
 * validates - `id`, `label`, `fullName`, `phoneNumber`, `addressLine1`,
 * `addressLine2`, `city`, `provinceOrState`, `postalCode`, `isDefault` -
 * with nullable fields written as explicit `null`.
 *
 * Input is the raw `users/{uid}/addresses/{addressId}` document, read
 * server-side (never client-supplied). `isDefault` is derived from the
 * authoritative `users/{uid}/addressDefault/pointer` document, never a stored
 * per-address boolean (there isn't one - see `address_firestore_mapper.dart`).
 *
 * Pure apart from importing the error factory.
 */

function str(value: unknown): string {
  return typeof value === "string" ? value : "";
}

function strOrNull(value: unknown): string | null {
  return typeof value === "string" && value.length > 0 ? value : null;
}

export interface DeliveryAddressSnapshot {
  id: string;
  label: string | null;
  fullName: string;
  phoneNumber: string;
  addressLine1: string;
  addressLine2: string | null;
  city: string;
  provinceOrState: string;
  postalCode: string;
  isDefault: boolean;
}

/** The address fields `isValidDeliveryAddress` requires to be non-empty. */
const REQUIRED_NON_EMPTY: ReadonlyArray<keyof DeliveryAddressSnapshot> = [
  "fullName",
  "phoneNumber",
  "addressLine1",
  "city",
  "provinceOrState",
  "postalCode",
];

export function buildDeliveryAddressSnapshot(
  addressId: string,
  addressData: Record<string, unknown>,
  defaultAddressId: string | null,
): DeliveryAddressSnapshot {
  const snapshot: DeliveryAddressSnapshot = {
    id: addressId,
    label: strOrNull(addressData.label),
    fullName: str(addressData.fullName),
    phoneNumber: str(addressData.phoneNumber),
    addressLine1: str(addressData.addressLine1),
    addressLine2: strOrNull(addressData.addressLine2),
    city: str(addressData.city),
    provinceOrState: str(addressData.provinceOrState),
    postalCode: str(addressData.postalCode),
    isDefault: addressId === defaultAddressId,
  };

  for (const field of REQUIRED_NON_EMPTY) {
    if (str(snapshot[field]).trim().length === 0) {
      // A saved address should never be missing these (isValidAddressCreate
      // enforces it), but a legacy / hand-edited doc might be - fail here
      // with a clear message rather than at the Phase 8.13.3 order write.
      throw errAddressIncomplete();
    }
  }

  return snapshot;
}
