import '../models/category/commerce_category_model.dart';
import '../models/product/product_category.dart';

// Firestore <-> CommerceCategoryModel mapping for `categories/{categoryId}`.
//
// Shared by FirestoreCategoryRepository and the developer-only seed export
// tool (`tool/export_category_seed.dart`), mirroring
// `product_firestore_mapper.dart`'s role for products. Unknown/missing/
// malformed fields fall back to safe defaults rather than throwing - this
// data is only ever written by our own seed tooling or the Admin write path,
// never by an untrusted client (mirrors `productModelFromFirestore`'s same
// convention).

CommerceCategoryModel categoryModelFromFirestore(
  String id,
  Map<String, dynamic> data,
) {
  return CommerceCategoryModel(
    categoryId: id,
    name: data['name'] as String? ?? '',
    key: data['key'] as String? ?? id,
    kind: _kindFromName(data['kind'] as String?),
    imageUrl: data['imageUrl'] as String? ?? '',
    isActive: data['isActive'] as bool? ?? true,
    sortOrder: (data['sortOrder'] as num?)?.toInt() ?? 0,
  );
}

extension CommerceCategoryModelFirestoreMapper on CommerceCategoryModel {
  /// Write direction. `key`/`categoryId` are always identical (see
  /// [CommerceCategoryModel]'s doc comment) - `key` is written explicitly
  /// anyway because it is a real field in the locked schema and
  /// `firestore.rules` validates it independently of the document ID.
  Map<String, dynamic> toFirestoreMap() {
    return {
      'name': name,
      'key': key,
      'kind': kind.name,
      'imageUrl': imageUrl,
      'isActive': isActive,
      'sortOrder': sortOrder,
    };
  }
}

/// Unknown/missing `kind` values must never silently resolve to
/// [ProductCategory.all] (a UI-only filter sentinel, never a real taxonomy
/// value) - falling back to [ProductCategory.furniture] instead keeps the
/// value inside the closed real-category set, matching the same
/// never-expose-the-sentinel discipline `product_firestore_mapper.dart`
/// applies to `publicationStatus` defaulting to `draft`, never a value that
/// would look more permissive than intended.
ProductCategory _kindFromName(String? name) {
  for (final k in ProductCategory.values) {
    if (k == ProductCategory.all) continue;
    if (k.name == name) return k;
  }
  return ProductCategory.furniture;
}
