import 'package:flutter/foundation.dart';

import '../../features/address/models/address_model.dart';

/// Canonical `users/{uid}/addresses` data contract (Phase 8.10), mirroring
/// `CategoryRepository`/`CommerceDatabase`'s established shape: reads stay
/// synchronous and reactive (a local list + `notifyListeners()`), writes are
/// `Future`-based from the start.
///
/// Unlike `CategoryRepository` (role-aware: Admin vs. customer), this
/// repository's scope is per-OWNER (uid) - a real implementation
/// (`FirestoreAddressRepository`) subscribes to the currently signed-in
/// user's own `users/{uid}/addresses` subcollection and re-subscribes on any
/// uid change, including a direct Customer A -> Customer B switch. See that
/// class's doc comment for the full uid-isolation/generation-guard design.
///
/// `isDefault` is NEVER a client-trusted per-document boolean under the
/// hood - see `FirestoreAddressRepository`'s doc comment for why a single
/// authoritative default-address pointer is used instead, with
/// [AddressModel.isDefault] derived from it. Callers of this interface don't
/// need to know that; [AddressModel.isDefault] is always correct to read.
abstract class AddressRepository extends ChangeNotifier {
  /// `true` until the first snapshot (or the first synchronous load, for the
  /// mock) has been received for the current uid.
  bool get isLoading;

  /// `true` if the most recent listener attempt failed (e.g. offline). A
  /// transient error for the SAME uid preserves the last-known [addresses]
  /// rather than clearing to empty - see `FirestoreAddressRepository`.
  bool get hasError;

  /// Sorted oldest-first by `createdAt`, with a deterministic document-ID
  /// tie-break when two addresses share the exact same `createdAt` (Phase
  /// 8.10 approved ordering; the tie-break closes a real determinism gap
  /// found by independent review - Dart's `List.sort` is not guaranteed
  /// stable, so relying on `createdAt` comparison alone could return a
  /// different order across two reads of the exact same data).
  List<AddressModel> get addresses;

  /// Monotonic counter that increments every time this repository's active
  /// identity (uid) changes - see `FirestoreAddressRepository`'s doc
  /// comment. A caller that captures this value before an async write and
  /// compares it after can detect "the signed-in user changed while this
  /// write was in flight" without depending on live-cache/listener timing
  /// (the bug this closes: `CustomerAddressState.addAddress` used to gate
  /// its optimistic selection on `addresses.any((a) => a.id == created.id)`,
  /// which could be falsely `false` for the SAME still-active user simply
  /// because the snapshot listener hadn't caught up yet - not just for a
  /// genuine account switch). [MockAddressRepository] always returns `0`
  /// (a single continuous session has no notion of an identity change).
  int get generation;

  /// The address currently marked default, or `null` if this user has no
  /// addresses yet. Derived from [addresses] - never a separate source of
  /// truth from the caller's point of view.
  AddressModel? get defaultAddress {
    for (final a in addresses) {
      if (a.isDefault) return a;
    }
    return null;
  }

  /// Creates a new address for the current signed-in user. The FIRST address
  /// a user ever creates automatically becomes their default regardless of
  /// [makeDefault] - handled atomically server-side (see
  /// `FirestoreAddressRepository.addAddress`'s doc comment), never inferred
  /// from this repository's local cache alone. For any LATER address,
  /// passing `makeDefault: true` atomically promotes it to default in the
  /// SAME write as its creation - never a separate follow-up call, which
  /// could race or silently no-op if it depended on the local cache/listener
  /// having caught up yet (the bug this closes).
  ///
  /// Returns the created [AddressModel] with its real, repository-allocated
  /// `id` and its correct, structurally-guaranteed [AddressModel.isDefault]
  /// - callers MUST use the returned model (not re-derive one, and not wait
  /// for a listener event) for any immediate post-save use (selection,
  /// navigation, promoting to default), per the Phase 8.10 correction that a
  /// client-generated `DateTime.now()`-based id is collision-prone.
  ///
  /// Throws a clean [StateError] ("You are not signed in.") if called while
  /// signed out - never silently creates local-only state.
  Future<AddressModel> addAddress(
    AddressDraft draft, {
    bool makeDefault = false,
  });

  /// Updates only the editable fields of an existing address, and never
  /// `createdAt` (immutable after creation). Passing `makeDefault: true`
  /// atomically promotes this address to default in the SAME write as the
  /// field update - see [addAddress]'s doc comment for why this must never
  /// be a separate follow-up call.
  Future<void> updateAddress(AddressModel address, {bool makeDefault = false});

  /// Atomically makes [addressId] the current user's default address via the
  /// authoritative default-pointer document - see
  /// `FirestoreAddressRepository`'s doc comment. Concurrent calls from two
  /// devices for two different addresses always converge to exactly one
  /// final default; they can never both "win" simultaneously.
  Future<void> setDefaultAddress(String addressId);

  /// Deletes [addressId]. If it was the current default, the default
  /// pointer automatically re-targets the earliest remaining address by
  /// `createdAt` (or clears to "no default" if none remain) - atomically,
  /// as part of the same operation, never as a separate step a concurrent
  /// device could race.
  Future<void> deleteAddress(String addressId);
}
