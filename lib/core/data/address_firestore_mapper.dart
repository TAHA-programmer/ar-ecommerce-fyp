import 'package:cloud_firestore/cloud_firestore.dart';

import '../../features/address/models/address_model.dart';

// Firestore <-> AddressModel mapping for `users/{uid}/addresses/{addressId}`
// (Phase 8.10). Every field uses an explicit `is T` type check (never an
// unsafe `as T?` cast) so one malformed document can never crash the
// listener - mirrors `order_firestore_mapper.dart`'s established
// convention.
//
// Deliberate schema correction from the original plan: the address document
// does NOT store `isDefault` at all. A per-document boolean would let two
// concurrent devices each locally believe they set a different address as
// default with no shared arbiter - the "two documents both marked default"
// race explicitly flagged for this phase. Instead, `isDefault` is derived by
// `FirestoreAddressRepository` from the single authoritative
// `users/{uid}/addressDefault/pointer` document - see that class's doc
// comment. [addressModelFromFirestore] therefore always takes the current
// default id as an explicit parameter rather than reading a stored field.

String _str(dynamic v, [String fallback = '']) => v is String ? v : fallback;
String? _strOrNull(dynamic v) => v is String ? v : null;

DateTime _dateFromTimestamp(dynamic value) {
  if (value is Timestamp) return value.toDate();
  return DateTime.now();
}

/// Read direction: a Firestore `addresses/{id}` document -> [AddressModel].
/// [currentDefaultId] is the live value of the authoritative default
/// pointer (`null` if none) - `isDefault` is computed as `id ==
/// currentDefaultId`, never read from the document itself.
AddressModel addressModelFromFirestore(
  String id,
  Map<String, dynamic> data,
  String? currentDefaultId,
) {
  return AddressModel(
    id: id,
    label: _strOrNull(data['label']),
    fullName: _str(data['fullName']),
    phoneNumber: _str(data['phoneNumber']),
    addressLine1: _str(data['addressLine1']),
    addressLine2: _strOrNull(data['addressLine2']),
    city: _str(data['city']),
    provinceOrState: _str(data['provinceOrState']),
    postalCode: _str(data['postalCode']),
    isDefault: id == currentDefaultId,
    createdAt: _dateFromTimestamp(data['createdAt']),
  );
}

extension AddressDraftFirestoreMapper on AddressDraft {
  /// Create-only write map. `createdAt` is always
  /// `FieldValue.serverTimestamp()` - deterministic ordering (Phase 8.10
  /// approved) requires a server-assigned value, never a client clock.
  /// `isDefault` is deliberately never written here - see this file's
  /// header comment.
  Map<String, dynamic> toFirestoreCreateMap() {
    return {
      'label': label,
      'fullName': fullName,
      'phoneNumber': phoneNumber,
      'addressLine1': addressLine1,
      'addressLine2': addressLine2,
      'city': city,
      'provinceOrState': provinceOrState,
      'postalCode': postalCode,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }
}

extension AddressModelFirestoreMapper on AddressModel {
  /// Update-only map for the editable fields - never `createdAt` (immutable
  /// after creation) and never `isDefault` (not a real field on this
  /// document at all - see this file's header comment).
  Map<String, dynamic> toFirestoreUpdateMap() {
    return {
      'label': label,
      'fullName': fullName,
      'phoneNumber': phoneNumber,
      'addressLine1': addressLine1,
      'addressLine2': addressLine2,
      'city': city,
      'provinceOrState': provinceOrState,
      'postalCode': postalCode,
    };
  }
}
