enum ProductExperienceType { none, roomAr, virtualTryOn }

extension ProductExperienceTypeExtension on ProductExperienceType {
  String get displayName {
    switch (this) {
      case ProductExperienceType.none:
        return 'No AR';
      case ProductExperienceType.roomAr:
        return 'Room AR';
      case ProductExperienceType.virtualTryOn:
        return 'Virtual Try-On';
    }
  }
}
