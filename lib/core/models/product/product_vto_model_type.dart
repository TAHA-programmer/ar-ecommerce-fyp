enum ProductVtoModelType { male, female }

extension ProductVtoModelTypeExtension on ProductVtoModelType {
  String get displayName {
    switch (this) {
      case ProductVtoModelType.male:
        return 'Male';
      case ProductVtoModelType.female:
        return 'Female';
    }
  }
}
