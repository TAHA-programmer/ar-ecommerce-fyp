// TWin AR — product seed export tool (Phase 8.5; deterministic since 9.2 R14).
//
// Developer-only, local-only. NOT Flutter app code, NOT deployed, NOT
// reachable from the mobile app - a dev tool under tool/, mirroring the
// scripts/super_admin_bootstrap/ and firestore-tests/ precedent of keeping
// one-off developer tooling out of lib/.
//
// Reads the canonical product seed data straight from
// `lib/core/data/mock_product_seed_data.dart` - the exact same
// `buildMockProductSeedData()` function `MockCommerceDatabase` itself
// calls - so nothing about the catalog (51 products total; ~36 of them
// Explore-visible) is hand-transcribed anywhere.
// This file deliberately imports ONLY that function and ProductModel's own
// plain-Dart dependencies - never `package:flutter/...` or
// `package:cloud_firestore/...` - because a plain `dart run` cannot
// compile anything that transitively needs `dart:ui` (only available under
// the full Flutter engine, e.g. `flutter test`/`flutter run`) or Firestore's
// native/FFI bindings.
//
// The field-name shape written here matches
// `lib/core/data/product_firestore_mapper.dart`'s `toFirestoreMap()`
// exactly (kept in sync by hand, since that file can't be imported here -
// see above); `addedDate` is exported as an ISO-8601 string rather than a
// Firestore `Timestamp`, since this JSON file is a plain intermediate
// artifact - scripts/seed_products/seed_products.mjs converts it to a real
// `admin.firestore.Timestamp` at write time.
//
// DETERMINISM (9.2 R14): `buildMockProductSeedData()` stamps `addedDate` from
// `DateTime.now()`, so a naive re-export churned all 51 timestamps. This tool
// now PRESERVES the authoritative `addedDate` of every product already present
// in `products_seed.json`; only a genuinely new product gets a fresh date, and
// only fields that actually changed in the mock seed move. A regression test
// (`test/tool/export_product_seed_test.dart`) proves repeated export is
// byte-stable.
//
// Usage (from the repo root):
//   dart run tool/export_product_seed.dart

import 'dart:convert';
import 'dart:io';

import 'package:twin_ar/core/data/mock_product_seed_data.dart';
import 'package:twin_ar/core/models/product/product_image_ref.dart';
import 'package:twin_ar/core/models/product/product_model.dart';

const String _outputPath = 'scripts/seed_products/products_seed.json';

void main() {
  final products = buildMockProductSeedData();

  List<dynamic>? previous;
  final existing = File(_outputPath);
  if (existing.existsSync()) {
    try {
      previous = jsonDecode(existing.readAsStringSync()) as List<dynamic>;
    } catch (_) {
      previous = null;
    }
  }

  final export = buildSeedExport(products, previous: previous);

  existing.createSync(recursive: true);
  existing.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(export),
  );

  stdout.writeln(
    'Exported ${products.length} products from buildMockProductSeedData() to '
    '$_outputPath (preserved addedDate for '
    '${(previous ?? const []).length} pre-existing products)',
  );
}

/// The deterministic seed export. For every product that already exists in
/// [previous] (by `id`), its authoritative `addedDate` is carried over
/// verbatim, so re-running with no source change is byte-identical. Every
/// other field comes from [products] (the canonical mock), so a recast in
/// `mock_product_seed_data.dart` still flows through.
List<Map<String, dynamic>> buildSeedExport(
  List<ProductModel> products, {
  List<dynamic>? previous,
}) {
  final priorAddedDateById = <String, String>{};
  for (final entry in previous ?? const []) {
    if (entry is Map<String, dynamic>) {
      final id = entry['id'];
      final added = entry['addedDate'];
      if (id is String && added is String) priorAddedDateById[id] = added;
    }
  }

  return products.map((p) {
    final map = _toJsonMap(p);
    final prior = priorAddedDateById[p.id];
    if (prior != null) map['addedDate'] = prior;
    return map;
  }).toList();
}

Map<String, dynamic> _toJsonMap(ProductModel p) {
  return {
    'id': p.id,
    'sku': p.sku,
    'title': p.title,
    'description': p.description,
    'categoryId': p.categoryId,
    'categoryKind': p.categoryKind.name,
    'subcategory': p.subcategory,
    'priceAmount': p.priceAmount,
    'originalPriceAmount': p.originalPriceAmount,
    'stockQuantity': p.stockQuantity,
    'isActive': p.isActive,
    'showInCatalog': p.showInCatalog,
    'publicationStatus': p.publicationStatus.name,
    'mainImage': _imageRefJson(p.mainImage),
    'galleryMedia': p.galleryMedia.map(_imageRefJson).toList(),
    'experienceType': p.experienceType.name,
    'vtoModelType': p.vtoModelType?.name,
    'availableColors': p.availableColors.map((c) => c.name).toList(),
    'availableSizes': p.availableSizes.map((s) => s.name).toList(),
    'defaultColor': p.defaultColor?.name,
    'defaultSize': p.defaultSize?.name,
    'specifications': p.specifications
        .map((s) => {'label': s.label, 'value': s.value})
        .toList(),
    'deliveryEstimate': p.deliveryEstimate,
    'warranty': p.warranty,
    'recommendationRank': p.recommendationRank,
    'popularityScore': p.popularityScore,
    // JSON-safe (ISO-8601), not a Firestore Timestamp - see file comment.
    'addedDate': p.addedDate.toIso8601String(),
    'rating': p.rating,
    'reviewCount': p.reviewCount,
    'arModelAssetPath': p.arModelAssetPath,
    'arScale': p.arScale,
    // Phase 9.2 R11/R12 production Room-AR contract - emitted only for a
    // product that carries it.
    ...?p.arMetadata?.toFirestoreFields(),
    'vtoGarmentAssetPath': p.vtoGarmentAssetPath,
  };
}

Map<String, dynamic> _imageRefJson(ProductImageRef ref) => {
  'path': ref.path,
  'source': ref.source.name,
  'altText': ref.altText,
};
