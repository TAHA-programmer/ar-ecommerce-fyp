enum ExploreSortOption {
  recommended,
  newest,
  priceLowToHigh,
  priceHighToLow,
  mostPopular,
}

extension ExploreSortOptionExtension on ExploreSortOption {
  String get label {
    switch (this) {
      case ExploreSortOption.recommended:
        return 'Recommended';
      case ExploreSortOption.newest:
        return 'Newest';
      case ExploreSortOption.priceLowToHigh:
        return 'Price: Low to High';
      case ExploreSortOption.priceHighToLow:
        return 'Price: High to Low';
      case ExploreSortOption.mostPopular:
        return 'Most Popular';
    }
  }
}
