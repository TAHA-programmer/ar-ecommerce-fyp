class AddressModel {
  final String id;
  final String? label;
  final String fullName;
  final String phoneNumber;
  final String addressLine1;
  final String? addressLine2;
  final String city;
  final String provinceOrState;
  final String postalCode;
  final bool isDefault;

  /// Server-assigned creation time - Phase 8.10 approved for deterministic
  /// cross-device ordering (`addresses` sorts oldest-first by this field,
  /// and "deleting the default selects the earliest remaining address" also
  /// resolves ties by this field). Defaults to `DateTime.now()` only for
  /// callers (tests, embedded order-snapshot fixtures) that don't care about
  /// real ordering - `FirestoreAddressRepository` always writes/reads the
  /// real server timestamp for a live address document.
  final DateTime createdAt;

  /// [id] is intentionally NOT auto-generated from `DateTime.now()` (the
  /// pre-Phase-8.10 behavior, which was collision-prone across devices/fast
  /// double-taps). It defaults to `''` - an obvious placeholder, never a
  /// real Firestore document ID - meant ONLY for a not-yet-persisted draft
  /// passed to `AddressRepository.addAddress`, which allocates and returns
  /// the real ID. Every other caller (edits, order snapshots, tests) must
  /// pass a real [id] explicitly.
  AddressModel({
    String? id,
    this.label,
    required this.fullName,
    required this.phoneNumber,
    required this.addressLine1,
    this.addressLine2,
    required this.city,
    required this.provinceOrState,
    required this.postalCode,
    this.isDefault = false,
    DateTime? createdAt,
  }) : id = id ?? '',
       createdAt = createdAt ?? DateTime.now();

  AddressModel copyWith({
    String? id,
    String? label,
    String? fullName,
    String? phoneNumber,
    String? addressLine1,
    String? addressLine2,
    String? city,
    String? provinceOrState,
    String? postalCode,
    bool? isDefault,
    DateTime? createdAt,
  }) {
    return AddressModel(
      id: id ?? this.id,
      label: label ?? this.label,
      fullName: fullName ?? this.fullName,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      addressLine1: addressLine1 ?? this.addressLine1,
      addressLine2: addressLine2 ?? this.addressLine2,
      city: city ?? this.city,
      provinceOrState: provinceOrState ?? this.provinceOrState,
      postalCode: postalCode ?? this.postalCode,
      isDefault: isDefault ?? this.isDefault,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  List<String> get formattedAddressLines {
    final lines = <String>[];
    if (addressLine1.isNotEmpty) lines.add(addressLine1);
    if (addressLine2 != null && addressLine2!.trim().isNotEmpty) {
      lines.add(addressLine2!.trim());
    }
    lines.add('$city, $provinceOrState  •  $postalCode');
    return lines;
  }
}

/// The editable fields of a not-yet-persisted address (Phase 8.10). Passed
/// to `AddressRepository.addAddress`, which allocates the real document ID
/// and decides `isDefault`/`createdAt` server-side - deliberately excludes
/// `id`/`isDefault`/`createdAt` so a caller can never pass a client-guessed
/// value for any of them.
class AddressDraft {
  final String? label;
  final String fullName;
  final String phoneNumber;
  final String addressLine1;
  final String? addressLine2;
  final String city;
  final String provinceOrState;
  final String postalCode;

  const AddressDraft({
    this.label,
    required this.fullName,
    required this.phoneNumber,
    required this.addressLine1,
    this.addressLine2,
    required this.city,
    required this.provinceOrState,
    required this.postalCode,
  });
}
