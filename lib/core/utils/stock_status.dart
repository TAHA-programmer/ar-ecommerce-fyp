enum StockStatus { inStock, lowStock, outOfStock }

extension StockStatusLabel on StockStatus {
  String get label => switch (this) {
    StockStatus.inStock => 'In Stock',
    StockStatus.lowStock => 'Low Stock',
    StockStatus.outOfStock => 'Out of Stock',
  };
}

/// Single shared definition of the stock-status bucketing rule used across
/// Admin surfaces (Dashboard, Product Management, Inventory):
/// 0 -> Out of Stock; 1..threshold -> Low Stock; above threshold -> In Stock.
StockStatus stockStatusForQuantity(int quantity, int lowStockThreshold) {
  if (quantity <= 0) return StockStatus.outOfStock;
  if (quantity <= lowStockThreshold) return StockStatus.lowStock;
  return StockStatus.inStock;
}
