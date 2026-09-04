enum ProductCategory { all, furniture, clothing, rugs, decor, lighting }

extension ProductCategoryExtension on ProductCategory {
  String get label {
    switch (this) {
      case ProductCategory.all:
        return 'All';
      case ProductCategory.furniture:
        return 'Furniture';
      case ProductCategory.clothing:
        return 'Clothing';
      case ProductCategory.rugs:
        return 'Rugs';
      case ProductCategory.decor:
        return 'Decor';
      case ProductCategory.lighting:
        return 'Lighting';
    }
  }
}
