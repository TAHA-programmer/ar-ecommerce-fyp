import 'package:flutter/material.dart';

/// The four selectable products in the Tier-2 Marker-AR engine.
///
/// Each maps 1:1 to a validated / physically-approved canonical GLB
/// (tracker §2.4–2.8). There is no QA/calibration object in production — the
/// 30 cm cube was removed from `twin_ar` in the R11/R12 pass (it survives only
/// in the isolated `_marker_ar_poc` as historical QA evidence).
enum MarkerArObject {
  chair,
  table,
  lamp,
  sofa;

  /// The native `setArMode` mode string.
  String get mode => name;

  /// The **current** Firestore `products/{id}` document id for this product
  /// (tracker §2.10 / §4). The coffee table and sofa *titles* change in
  /// R13/R14; these ids do not. Used to look the product up in
  /// `RoomArProductManifest` for R10 Storage delivery.
  String get firestoreProductId => switch (this) {
    MarkerArObject.chair => 'luna-accent-chair',
    MarkerArObject.table => 'glass-coffee-table',
    MarkerArObject.lamp => 'modern-table-lamp',
    MarkerArObject.sofa => 'luna-3-seater-sofa',
  };

  /// Reverse of [firestoreProductId] — the [MarkerArObject] for a live
  /// `products/{id}` document id, or `null` when the product is not one of the
  /// four physically-approved Room-AR products. The customer "Start AR" launch
  /// (R15/R17) uses this to refuse any other product outright.
  static MarkerArObject? fromFirestoreProductId(String productId) =>
      switch (productId) {
        'luna-accent-chair' => MarkerArObject.chair,
        'glass-coffee-table' => MarkerArObject.table,
        'modern-table-lamp' => MarkerArObject.lamp,
        'luna-3-seater-sofa' => MarkerArObject.sofa,
        _ => null,
      };

  /// Short selector label.
  String get label => switch (this) {
    MarkerArObject.chair => 'Chair',
    MarkerArObject.table => 'Table',
    MarkerArObject.lamp => 'Lamp',
    MarkerArObject.sofa => 'Sofa',
  };

  /// Full display name for status text.
  String get displayName => switch (this) {
    MarkerArObject.chair => 'Luna Accent Chair',
    MarkerArObject.table => 'Round Wood Coffee Table',
    MarkerArObject.lamp => 'Modern Table Lamp',
    MarkerArObject.sofa => 'Luna Right-Chaise Sectional Sofa',
  };

  IconData get icon => switch (this) {
    MarkerArObject.chair => Icons.chair_outlined,
    MarkerArObject.table => Icons.table_restaurant_outlined,
    MarkerArObject.lamp => Icons.light_outlined,
    MarkerArObject.sofa => Icons.weekend_outlined,
  };
}
