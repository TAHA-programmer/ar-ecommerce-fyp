import '../product/product_category.dart';

/// A real, Firestore-backed commerce category (`categories/{categoryId}`,
/// Phase 8.8 - Dynamic Categories Foundation).
///
/// Deliberately NOT named `CategoryModel` - that name is already taken by
/// `lib/features/home/models/category_model.dart`, Home's static curated-tile
/// model, which this phase does not touch. `CommerceCategoryModel` names the
/// distinction explicitly rather than relying on import aliasing.
///
/// [categoryId] is always identical to [key] - the Firestore document ID IS
/// the stable slug (see `FirestoreCategoryRepository.addCategory`'s doc
/// comment for the transactional creation flow that guarantees this). Both
/// are exposed as separate fields only because the locked schema names them
/// separately; nothing in this codebase ever constructs one without the
/// other matching.
///
/// [kind] reuses the existing [ProductCategory] enum (never `.all`) rather
/// than introducing a second taxonomy type - this is exactly the role
/// Correction 2 in `09_BACKEND_INTEGRATION_PLAN.md` already locked for
/// `ProductCategory` long-term ("repurposed as the closed AR/VTO-eligibility
/// taxonomy type"). `key`/`kind` are immutable after creation (enforced by
/// `firestore.rules` and never exposed as editable in the Admin UI) -
/// `name`/`imageUrl`/`isActive`/`sortOrder` are the only editable fields.
class CommerceCategoryModel {
  final String categoryId;
  final String name;
  final String key;
  final ProductCategory kind;
  final String imageUrl;
  final bool isActive;
  final int sortOrder;

  const CommerceCategoryModel({
    required this.categoryId,
    required this.name,
    required this.key,
    required this.kind,
    required this.imageUrl,
    required this.isActive,
    required this.sortOrder,
  });

  /// `true` for the five originally-seeded categories - `ProductModel`'s
  /// legacy `category` field (Firestore dual-read fallback,
  /// `product_firestore_mapper.dart`) and the Phase 8.8b `categoryId`
  /// backfill migration both depend on `categoryId == this legacy enum
  /// name` for exactly these five. Permanently protected from hard
  /// deletion, both in `AdminProductManagementViewModel`/
  /// `FirestoreCategoryRepository.deleteCategory` and in
  /// `firestore.rules`. A category created later by an Admin is never one
  /// of these, regardless of what `key`/`kind` it happens to be given.
  static const Set<String> seededCategoryIds = {
    'furniture',
    'clothing',
    'rugs',
    'decor',
    'lighting',
  };

  bool get isSeeded => seededCategoryIds.contains(categoryId);

  CommerceCategoryModel copyWith({
    String? name,
    String? imageUrl,
    bool? isActive,
    int? sortOrder,
  }) {
    return CommerceCategoryModel(
      categoryId: categoryId,
      name: name ?? this.name,
      key: key,
      kind: kind,
      imageUrl: imageUrl ?? this.imageUrl,
      isActive: isActive ?? this.isActive,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }
}
