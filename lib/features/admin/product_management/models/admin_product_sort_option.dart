enum AdminProductSortOption {
  newest,
  nameAZ,
  nameZA,
  priceLowToHigh,
  priceHighToLow,
  stockLowToHigh,
  stockHighToLow,
}

extension AdminProductSortOptionExtension on AdminProductSortOption {
  String get label {
    switch (this) {
      case AdminProductSortOption.newest:
        return 'Newest';
      case AdminProductSortOption.nameAZ:
        return 'Name A-Z';
      case AdminProductSortOption.nameZA:
        return 'Name Z-A';
      case AdminProductSortOption.priceLowToHigh:
        return 'Price Low to High';
      case AdminProductSortOption.priceHighToLow:
        return 'Price High to Low';
      case AdminProductSortOption.stockLowToHigh:
        return 'Stock Low to High';
      case AdminProductSortOption.stockHighToLow:
        return 'Stock High to Low';
    }
  }
}
