import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/core/models/product/product_image_ref.dart';
import 'package:twin_ar/core/widgets/product_image_view.dart';

void main() {
  group('ProductImageView Tests', () {
    testWidgets('renders Image.asset when source is asset', (
      WidgetTester tester,
    ) async {
      final ref = ProductImageRef(
        path: 'assets/test_image.png',
        source: ProductImageSource.asset,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ProductImageView(imageRef: ref)),
        ),
      );

      final imageFinder = find.byType(Image);
      expect(imageFinder, findsOneWidget);

      final Image imageWidget = tester.widget(imageFinder);
      expect(imageWidget.image, isA<AssetImage>());
      expect(
        (imageWidget.image as AssetImage).assetName,
        'assets/test_image.png',
      );
    });

    testWidgets('renders Image.file when source is file', (
      WidgetTester tester,
    ) async {
      final ref = ProductImageRef(
        path: 'path/to/local/file.png',
        source: ProductImageSource.file,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ProductImageView(imageRef: ref)),
        ),
      );

      final imageFinder = find.byType(Image);
      expect(imageFinder, findsOneWidget);

      final Image imageWidget = tester.widget(imageFinder);
      expect(imageWidget.image, isA<FileImage>());
      expect(
        (imageWidget.image as FileImage).file.path,
        'path/to/local/file.png',
      );
    });

    testWidgets('renders Image.network when source is network', (
      WidgetTester tester,
    ) async {
      final ref = ProductImageRef(
        path: 'https://example.com/image.png',
        source: ProductImageSource.network,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ProductImageView(imageRef: ref)),
        ),
      );

      final imageFinder = find.byType(Image);
      expect(imageFinder, findsOneWidget);

      final Image imageWidget = tester.widget(imageFinder);
      expect(imageWidget.image, isA<NetworkImage>());
      expect(
        (imageWidget.image as NetworkImage).url,
        'https://example.com/image.png',
      );
    });

    testWidgets('error builder fallback can render if image fails', (
      WidgetTester tester,
    ) async {
      // In a real widget test, triggering the error builder of Image.asset natively without a real missing asset
      // can be tricky to guarantee synchronously, but we can verify the widget has the error builder parameter.
      final ref = ProductImageRef(
        path: 'assets/non_existent.png',
        source: ProductImageSource.asset,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ProductImageView(imageRef: ref)),
        ),
      );

      final imageFinder = find.byType(Image);
      final Image imageWidget = tester.widget(imageFinder);
      expect(imageWidget.errorBuilder, isNotNull);
    });
  });
}
