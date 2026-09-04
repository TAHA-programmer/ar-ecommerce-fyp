import 'package:flutter/foundation.dart';
import '../models/category/commerce_category_model.dart';
import '../models/product/product_category.dart';

/// Canonical `categories` data contract (Phase 8.8 - Dynamic Categories
/// Foundation), mirroring `CommerceDatabase`'s established shape: reads stay
/// synchronous and reactive (a local list + `notifyListeners()`), writes are
/// `Future`-based from the start.
///
/// Deliberately a separate, narrow interface from `CommerceDatabase` - not a
/// new method bolted onto it - matching this project's existing
/// `StorageService`/`UserProfileRepository` precedent of one small
/// purpose-fit interface per genuinely distinct concern, not a speculative
/// general one.
abstract class CategoryRepository extends ChangeNotifier {
  /// `true` until the first snapshot (or the first synchronous load, for the
  /// mock) has been received. Lets the Admin UI show a loading state instead
  /// of a misleading "No categories found" empty state during the initial
  /// fetch.
  bool get isLoading;

  /// `true` if the most recent Firestore listener attempt failed (e.g.
  /// offline). [categories] falls back to the last-known list (or empty, if
  /// none was ever loaded) - this flag lets the UI show a recoverable error
  /// state rather than silently look like "zero categories exist".
  bool get hasError;

  List<CommerceCategoryModel> get categories;

  /// Looks up a category by ID within the currently-loaded [categories].
  /// Returns `null` if it isn't there - either because it was deleted, or
  /// (for a customer-role session, which only ever loads active categories)
  /// because it's inactive. Callers that need to display a category's name
  /// must treat a `null` result as expected, not exceptional - see
  /// `CommerceCategoryModel`'s usage in category-name display sites, which
  /// fall back to the product's denormalized `categoryKind.label` when this
  /// returns `null`.
  CommerceCategoryModel? byId(String categoryId) {
    for (final c in categories) {
      if (c.categoryId == categoryId) return c;
    }
    return null;
  }

  /// Creates a new category. [name] is trimmed/validated and slugified into
  /// the stable `key`/document-ID by the implementation; [kind] must not be
  /// [ProductCategory.all]. Uniqueness of the derived key is enforced by a
  /// Firestore transaction (see `FirestoreCategoryRepository.addCategory`'s
  /// doc comment) - this method throws a clean [StateError] on collision,
  /// mirroring `FirestoreCommerceDatabase.addProduct`'s established
  /// duplicate-id convention. Case-insensitive duplicate DISPLAY names are a
  /// separate, application-level check - see that same doc comment for why
  /// it cannot be the transaction's job.
  Future<CommerceCategoryModel> addCategory({
    required String name,
    required ProductCategory kind,
    String imageUrl,
    bool isActive,
  });

  /// Updates only `name`/`imageUrl`/`isActive`/`sortOrder` on an existing
  /// category - `key`/`kind` are immutable after creation and this method
  /// never attempts to change them (`firestore.rules` independently rejects
  /// any attempt to).
  Future<void> updateCategory(CommerceCategoryModel updated);

  /// Deletes a category. Implementations MUST refuse to delete any of the
  /// five permanently protected seeded category IDs
  /// ([CommerceCategoryModel.seededCategoryIds]) with a clean [StateError] -
  /// this is a structural invariant of the `categories` collection itself,
  /// enforced here independently of (and in addition to) the ViewModel's
  /// separate zero-product-count check and `firestore.rules`' own delete
  /// rule.
  Future<void> deleteCategory(String categoryId);
}
