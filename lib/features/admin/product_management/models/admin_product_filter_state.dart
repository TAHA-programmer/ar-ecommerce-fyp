import '../../../../core/models/product/product_category.dart';

enum AdminProductStatusFilter { all, active, inactive }

enum AdminProductStockFilter { all, inStock, lowStock, outOfStock }

enum AdminProductArFilter { all, none, roomAr, virtualTryOn }

class AdminProductFilterState {
  final ProductCategory? category; // null means 'All'
  final AdminProductStatusFilter status;
  final AdminProductStockFilter stock;
  final AdminProductArFilter arType;

  const AdminProductFilterState({
    this.category,
    this.status = AdminProductStatusFilter.all,
    this.stock = AdminProductStockFilter.all,
    this.arType = AdminProductArFilter.all,
  });

  factory AdminProductFilterState.defaultState() {
    return const AdminProductFilterState();
  }

  AdminProductFilterState copyWith({
    ProductCategory? category,
    AdminProductStatusFilter? status,
    AdminProductStockFilter? stock,
    AdminProductArFilter? arType,
    bool clearCategory = false,
  }) {
    return AdminProductFilterState(
      category: clearCategory ? null : (category ?? this.category),
      status: status ?? this.status,
      stock: stock ?? this.stock,
      arType: arType ?? this.arType,
    );
  }

  bool get hasActiveFilters =>
      category != null ||
      status != AdminProductStatusFilter.all ||
      stock != AdminProductStockFilter.all ||
      arType != AdminProductArFilter.all;

  int get activeFilterCount {
    int count = 0;
    if (category != null) count++;
    if (status != AdminProductStatusFilter.all) count++;
    if (stock != AdminProductStockFilter.all) count++;
    if (arType != AdminProductArFilter.all) count++;
    return count;
  }
}
