enum AdminCategorySortOption { nameAZ, nameZA, mostProducts, fewestProducts }

extension AdminCategorySortOptionExtension on AdminCategorySortOption {
  String get label {
    switch (this) {
      case AdminCategorySortOption.nameAZ:
        return 'Name A-Z';
      case AdminCategorySortOption.nameZA:
        return 'Name Z-A';
      case AdminCategorySortOption.mostProducts:
        return 'Most Products';
      case AdminCategorySortOption.fewestProducts:
        return 'Fewest Products';
    }
  }
}
