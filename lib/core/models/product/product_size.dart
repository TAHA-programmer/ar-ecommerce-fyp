enum ProductSize { s, m, l, xl, xxl }

extension ProductSizeExtension on ProductSize {
  String get label {
    switch (this) {
      case ProductSize.s:
        return 'S';
      case ProductSize.m:
        return 'M';
      case ProductSize.l:
        return 'L';
      case ProductSize.xl:
        return 'XL';
      case ProductSize.xxl:
        return 'XXL';
    }
  }
}
