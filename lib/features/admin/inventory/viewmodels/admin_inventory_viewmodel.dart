import 'package:flutter/foundation.dart';

import '../../../../core/data/category_repository.dart';
import '../../../../core/data/commerce_database.dart';
import '../../../../core/models/product/product_category.dart';
import '../../../../core/models/product/product_model.dart';
import '../../../../core/utils/stock_status.dart';

class _InventoryRowState {
  int? pendingOverride;
  String? error;

  /// Phase 8.11 - the client-side "just saved" timestamp shown immediately
  /// after a successful save, only while [awaitingServerEcho] is still true.
  DateTime? optimisticStamp;

  /// True from a successful save until the authoritative server-resolved
  /// `lastStockUpdatedAt` for this row has been observed in the shared
  /// database. While true, [lastUpdatedFor] returns [optimisticStamp];
  /// once cleared it returns the persisted `ProductModel.lastStockUpdatedAt`
  /// and never reverts to the optimistic value.
  bool awaitingServerEcho = false;

  /// The row's persisted `lastStockUpdatedAt` captured *before* the pending
  /// save. The echo is considered received when the shared database reports
  /// a non-null value different from this baseline (a `serverTimestamp()`
  /// write always resolves to a distinct, later instant; the Mock uses a
  /// strictly-increasing stand-in for the same guarantee).
  DateTime? echoBaseline;
}

/// Owns Inventory's per-row staged-edit state on top of the shared
/// [CommerceDatabase]. It never holds its own copy of product/stock
/// data - every read falls back to the canonical [ProductModel.stockQuantity]
/// until a row is explicitly staged, and every write goes through
/// [CommerceDatabase.updateStock] so Dashboard, Product Management,
/// Customer surfaces, and Checkout all observe the same change.
class AdminInventoryViewModel extends ChangeNotifier {
  final CommerceDatabase _db;
  final CategoryRepository _categoryRepository;

  AdminInventoryViewModel(this._db, this._categoryRepository) {
    _db.addListener(_onDatabaseChanged);
  }

  final Map<String, _InventoryRowState> _rows = {};

  String _searchQuery = '';
  String get searchQuery => _searchQuery;

  ProductCategory _selectedCategory = ProductCategory.all;
  ProductCategory get selectedCategory => _selectedCategory;

  bool _lowStockOnly = false;
  bool get lowStockOnly => _lowStockOnly;

  int get lowStockThreshold => CommerceDatabase.lowStockThreshold;

  void _onDatabaseChanged() {
    _reconcileServerEchoes();
    notifyListeners();
  }

  /// Clears the optimistic "just saved" marker on any row whose
  /// authoritative server-resolved `lastStockUpdatedAt` has now landed in
  /// the shared database, so the card converges from the client "just now"
  /// value to the real server timestamp without ever permanently masking
  /// it. A pending `serverTimestamp()` write can briefly echo back as null
  /// (see [_committedLastStockUpdatedAt]); that is not yet the echo, so the
  /// row stays optimistic until a real, distinct value arrives.
  void _reconcileServerEchoes() {
    for (final entry in _rows.entries) {
      final row = entry.value;
      if (!row.awaitingServerEcho) continue;
      final current = _committedLastStockUpdatedAt(entry.key);
      if (current != null && current != row.echoBaseline) {
        row.awaitingServerEcho = false;
        row.optimisticStamp = null;
        row.echoBaseline = null;
      }
    }
  }

  DateTime? _committedLastStockUpdatedAt(String productId) {
    try {
      return _db.getProductById(productId).lastStockUpdatedAt;
    } catch (_) {
      // Product filtered out / deleted - no persisted timestamp to show.
      return null;
    }
  }

  @override
  void dispose() {
    _db.removeListener(_onDatabaseChanged);
    super.dispose();
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  void setCategory(ProductCategory category) {
    _selectedCategory = category;
    notifyListeners();
  }

  void setLowStockOnly(bool value) {
    _lowStockOnly = value;
    notifyListeners();
  }

  List<ProductModel> get filteredProducts {
    var result = _db.products;

    final query = _searchQuery.trim().toLowerCase();
    if (query.isNotEmpty) {
      // categoryId->name lookup built once per filter pass, not once per
      // product - matches products by their real assigned category name
      // (e.g. "Outdoor") in addition to the broad kind label ("Furniture").
      final categoryNameById = {
        for (final c in _categoryRepository.categories) c.categoryId: c.name,
      };
      result = result.where((p) {
        final titleMatches = p.title.toLowerCase().contains(query);
        final skuMatches = p.sku.toLowerCase().contains(query);
        final kindMatches = p.categoryKind.label.toLowerCase().contains(query);
        final categoryName = categoryNameById[p.categoryId] ?? '';
        final categoryNameMatches = categoryName.toLowerCase().contains(query);
        return titleMatches || skuMatches || kindMatches || categoryNameMatches;
      }).toList();
    }

    if (_selectedCategory != ProductCategory.all) {
      result = result
          .where((p) => p.categoryKind == _selectedCategory)
          .toList();
    }

    if (_lowStockOnly) {
      result = result.where((p) {
        return stockStatusForQuantity(p.stockQuantity, lowStockThreshold) ==
            StockStatus.lowStock;
      }).toList();
    }

    return result;
  }

  int get totalProductsCount => filteredProducts.length;

  // --- Per-row staged state ---

  int _committedQuantity(String productId) =>
      _db.getProductById(productId).stockQuantity;

  int pendingQuantityFor(String productId) {
    return _rows[productId]?.pendingOverride ?? _committedQuantity(productId);
  }

  String? errorFor(String productId) => _rows[productId]?.error;

  /// The "Last updated" timestamp for a row.
  ///
  /// Phase 8.11: immediately after a successful save this returns the
  /// client-side optimistic stamp (shown as "just now"); once the shared
  /// database delivers the authoritative server-resolved
  /// `ProductModel.lastStockUpdatedAt` (typically within a second, via the
  /// Firestore snapshot listener - or synchronously for the Mock), the row
  /// converges to that persisted value and never reverts. If no session
  /// save is pending, it returns the persisted value directly, so the
  /// timestamp survives a screen reload / a fresh ViewModel and is
  /// consistent across Admin devices. `null` renders the existing
  /// "Last updated: —" empty state.
  DateTime? lastUpdatedFor(String productId) {
    final row = _rows[productId];
    if (row != null && row.awaitingServerEcho && row.optimisticStamp != null) {
      return row.optimisticStamp;
    }
    return _committedLastStockUpdatedAt(productId);
  }

  bool hasPendingChange(String productId) {
    final row = _rows[productId];
    if (row == null) return false;
    if (row.error != null) return true;
    return row.pendingOverride != null &&
        row.pendingOverride != _committedQuantity(productId);
  }

  StockStatus stockStatusFor(String productId) {
    return stockStatusForQuantity(
      pendingQuantityFor(productId),
      lowStockThreshold,
    );
  }

  _InventoryRowState _rowFor(String productId) =>
      _rows.putIfAbsent(productId, () => _InventoryRowState());

  void _stagePending(String productId, int quantity) {
    final row = _rowFor(productId);
    row.pendingOverride = quantity;
    row.error = null;
    notifyListeners();
  }

  void _stageError(String productId, String message) {
    final row = _rowFor(productId);
    row.error = message;
    notifyListeners();
  }

  void incrementQuantity(String productId) {
    _stagePending(productId, pendingQuantityFor(productId) + 1);
  }

  void decrementQuantity(String productId) {
    final next = pendingQuantityFor(productId) - 1;
    _stagePending(productId, next < 0 ? 0 : next);
  }

  /// Parses and validates raw text from the direct-input field. Whole,
  /// non-negative integers stage a new pending value; anything else stages
  /// an inline validation error and leaves the last valid pending value
  /// untouched so Save stays blocked without discarding prior progress.
  void setPendingQuantityFromText(String productId, String rawText) {
    final trimmed = rawText.trim();
    if (trimmed.isEmpty) {
      _stageError(productId, 'Stock quantity is required.');
      return;
    }

    final parsed = num.tryParse(trimmed);
    if (parsed == null) {
      _stageError(productId, 'Enter a valid whole number.');
      return;
    }
    if (parsed < 0) {
      _stageError(productId, 'Stock cannot be negative.');
      return;
    }
    if (parsed != parsed.truncate()) {
      _stageError(productId, 'Only whole numbers are allowed.');
      return;
    }

    _stagePending(productId, parsed.toInt());
  }

  /// Validates and commits the staged quantity through the shared
  /// [CommerceDatabase]. Returns true on success. A false return with no
  /// error set means the row had nothing valid to save; a false return with
  /// [errorFor] set means validation (or, defensively, the write itself)
  /// failed and the row was left untouched in the database.
  Future<bool> saveProduct(String productId) async {
    final row = _rows[productId];
    if (row?.error != null) return false;

    final pending = pendingQuantityFor(productId);
    // Capture the persisted timestamp BEFORE the write so the echo can be
    // detected as "a new, distinct value has landed" (see
    // _reconcileServerEchoes).
    final echoBaseline = _committedLastStockUpdatedAt(productId);
    try {
      await _db.updateStock(productId, pending);
      final updatedRow = _rowFor(productId);
      updatedRow.pendingOverride = null;
      updatedRow.error = null;
      updatedRow.optimisticStamp = DateTime.now();
      updatedRow.echoBaseline = echoBaseline;
      updatedRow.awaitingServerEcho = true;
      // The Mock resolves its timestamp synchronously, so the echo may
      // already be observable; Firestore converges on the next snapshot.
      _reconcileServerEchoes();
      notifyListeners();
      return true;
    } catch (_) {
      _stageError(productId, 'Failed to update stock. Please try again.');
      return false;
    }
  }
}
