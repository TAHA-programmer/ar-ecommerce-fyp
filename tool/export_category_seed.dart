// TWin AR — category seed export tool (Phase 8.8).
//
// Developer-only, local-only. NOT Flutter app code, NOT deployed, NOT
// reachable from the mobile app - mirrors tool/export_product_seed.dart
// exactly, same reason (a plain `dart run` cannot compile anything that
// transitively needs `dart:ui`/Firestore's native bindings).
//
// Reads the five canonical seeded categories straight from
// `lib/core/data/category_seed_data.dart`'s `buildCategorySeedData()` - the
// single Dart source of truth - so nothing is hand-transcribed into the
// Node seed script. `sourceImageAssetPath` is exported as-is (a repo-root-
// relative bundled asset path); `scripts/seed_categories/seed_categories.mjs`
// resolves and uploads it - this JSON file never contains a Storage URL.
//
// Usage (from the repo root):
//   dart run tool/export_category_seed.dart

import 'dart:convert';
import 'dart:io';

import 'package:twin_ar/core/data/category_seed_data.dart';

const String _outputPath = 'scripts/seed_categories/categories_seed.json';

void main() {
  final categories = buildCategorySeedData();

  final export = categories
      .map(
        (c) => {
          'key': c.key,
          'name': c.name,
          'kind': c.kind.name,
          'sortOrder': c.sortOrder,
          'sourceImageAssetPath': c.sourceImageAssetPath,
        },
      )
      .toList();

  final file = File(_outputPath);
  file.createSync(recursive: true);
  file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(export));

  stdout.writeln(
    'Exported ${categories.length} categories from '
    'buildCategorySeedData() to $_outputPath',
  );
}
