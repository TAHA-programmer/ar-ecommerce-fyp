import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/favorite/favorite_model.dart';

// Firestore <-> FavoriteModel mapping for `users/{uid}/favorites/{productId}`
// (Phase 8.10). Document ID IS the productId (dedupes for free - no
// separate uniqueness concern the way addresses/cart need one). Only one
// real field (`addedAt`) - still uses an explicit type check rather than an
// unsafe cast, matching every other mapper in this codebase.

DateTime _dateFromTimestamp(dynamic value) {
  if (value is Timestamp) return value.toDate();
  return DateTime.now();
}

FavoriteModel favoriteModelFromFirestore(
  String productId,
  Map<String, dynamic> data,
) {
  return FavoriteModel(
    productId: productId,
    addedAt: _dateFromTimestamp(data['addedAt']),
  );
}

/// Create-only write map (a favorite is never updated in place - it's
/// either present or absent).
Map<String, dynamic> favoriteToFirestoreCreateMap() {
  return {'addedAt': FieldValue.serverTimestamp()};
}
