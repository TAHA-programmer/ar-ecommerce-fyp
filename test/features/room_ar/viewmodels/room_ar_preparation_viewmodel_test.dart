import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/core/data/mock_commerce_database.dart';
import 'package:twin_ar/core/models/product/product_ar_metadata.dart';
import 'package:twin_ar/core/models/product/product_category.dart';
import 'package:twin_ar/core/models/product/product_experience_type.dart';
import 'package:twin_ar/core/models/product/product_image_ref.dart';
import 'package:twin_ar/core/models/product/product_model.dart';
import 'package:twin_ar/features/room_ar/capability/room_ar_capability.dart';
import 'package:twin_ar/features/room_ar/marker_ar/models/marker_ar_object.dart';
import 'package:twin_ar/features/room_ar/viewmodels/room_ar_preparation_viewmodel.dart';
import 'package:twin_ar/features/product_details/repositories/mock_product_details_repository.dart';

import '../capability/fake_capability_service.dart';

void main() {
  late MockCommerceDatabase database;
  late MockProductDetailsRepository repository;

  setUp(() {
    database = MockCommerceDatabase();
    repository = MockProductDetailsRepository(database, simulateDelay: false);
  });

  RoomArPreparationViewModel build(
    String id, {
    RoomArDeviceCapabilities caps = FakeRoomArCapabilityService.infinix,
  }) => RoomArPreparationViewModel(
    repository: repository,
    capabilityService: FakeRoomArCapabilityService(caps),
    productId: id,
  );

  Future<void> settle() => Future.delayed(const Duration(milliseconds: 50));

  group('RoomArPreparationViewModel', () {
    test('successfully loads roomAr product', () async {
      final vm = build('luna-accent-chair');
      expect(vm.isLoading, isTrue);
      await settle();
      expect(vm.isLoading, isFalse);
      expect(vm.error, isNull);
      expect(vm.product!.summary.id, 'luna-accent-chair');
    });

    test('shows error for non-roomAr product', () async {
      final vm = build('mens-oxford-shirt');
      await settle();
      expect(vm.error, 'This product does not support Room AR.');
      expect(vm.product, isNull);
    });

    test('shows error for unknown product', () async {
      final vm = build('unknown_product');
      await settle();
      expect(vm.error, 'Failed to load product details');
    });

    test('approved product + ARCore-capable device → Tier 1, correct session '
        'args (Phase 9.2 R6)', () async {
      final vm = build(
        'luna-accent-chair',
        caps: FakeRoomArCapabilityService.arCoreDevice,
      );
      await settle();
      expect(vm.resolvedTier, RoomArTier.tier1Arcore);
      expect(vm.canStartArCore, isTrue);
      expect(vm.canStartAr, isFalse);
      expect(vm.canPreview, isFalse);
      final args = vm.sessionArgs!;
      expect(args.firestoreProductId, 'luna-accent-chair');
      expect(args.metadata.isRenderable, isTrue);
    });

    test(
      'approved product + camera device → Tier 2, correct session args',
      () async {
        final vm = build('luna-accent-chair');
        await settle();
        expect(vm.resolvedTier, RoomArTier.tier2Marker);
        expect(vm.canStartAr, isTrue);
        expect(vm.canPreview, isFalse);
        final args = vm.sessionArgs!;
        expect(args.firestoreProductId, 'luna-accent-chair');
        expect(args.object, MarkerArObject.chair);
        expect(args.metadata.isRenderable, isTrue);
        expect(args.productTitle, 'Luna Accent Chair');
      },
    );

    test('approved product + camera blocked → Tier 3 preview', () async {
      final vm = build(
        'glass-coffee-table',
        caps: FakeRoomArCapabilityService.noCameraAr,
      );
      await settle();
      expect(vm.resolvedTier, RoomArTier.tier3Preview);
      expect(vm.canPreview, isTrue);
      expect(vm.canStartAr, isFalse);
      expect(vm.sessionArgs, isNotNull); // same args feed the preview route
    });

    test(
      'approved product + no GLES3 → device unsupported, no launch',
      () async {
        final vm = build(
          'modern-table-lamp',
          caps: FakeRoomArCapabilityService.noGles,
        );
        await settle();
        expect(vm.resolvedTier, RoomArTier.unsupported);
        expect(vm.canStartAr, isFalse);
        expect(vm.canPreview, isFalse);
        expect(vm.deviceUnsupported, isTrue);
      },
    );

    test('roomAr product with no approved model: no tier, no launch, and the '
        'device is never even probed', () async {
      final fake = FakeRoomArCapabilityService();
      final vm = RoomArPreparationViewModel(
        repository: repository,
        capabilityService: fake,
        productId: 'other-product-3', // roomAr, no arMetadata
      );
      await settle();
      expect(vm.product, isNotNull);
      expect(vm.canStartAr, isFalse);
      expect(vm.canPreview, isFalse);
      expect(vm.deviceUnsupported, isFalse);
      expect(vm.sessionArgs, isNull);
      expect(fake.detectCalls, 0);
    });

    group('Phase 9.2 dynamic eligibility (MarkerArObject blocker removed)', () {
      test(
        'a coverage-expansion product (no bundled/native rendering slot) is '
        'eligible and launches with its own real model — never a stale one',
        () async {
          final vm = build('velvet-armchair');
          await settle();
          expect(vm.canStartAr, isTrue);
          final args = vm.sessionArgs!;
          expect(args.firestoreProductId, 'velvet-armchair');
          // Not one of the four originally-bundled products — no compiled-in
          // rendering slot, so `object` must stay null (never a placeholder
          // that could point the native renderer at the wrong bundled asset).
          expect(args.object, isNull);
          expect(
            args.nativeMode,
            'velvet-armchair',
          ); // falls through to its own product id, unique per product
          expect(
            args.metadata.storagePath,
            'products/velvet-armchair/ar/model-v1.glb',
          );
          expect(args.productTitle, 'Velvet Armchair');
        },
      );

      test('a shared-design beige-ar-in-stock product resolves its own storage '
          'path, not another member of its group', () async {
        final vm = build('beige-ar-in-stock-5'); // Beige AR Rug group
        await settle();
        expect(vm.sessionArgs, isNotNull);
        final args = vm.sessionArgs!;
        expect(args.firestoreProductId, 'beige-ar-in-stock-5');
        expect(
          args.metadata.storagePath,
          'products/beige-ar-in-stock-5/ar/model-v1.glb',
        );
        expect(
          args.metadata.storagePath,
          isNot(contains('beige-ar-in-stock-7')),
        );
      });

      test(
        'a genuinely new Admin-created product id — never added to '
        'RoomArProductManifest or any Dart enum — is still eligible',
        () async {
          database.addProduct(
            ProductModel(
              id: 'future-admin-product-42',
              sku: 'SKU-FUTURE',
              title: 'A Brand New Product',
              description: 'd',
              categoryId: 'furniture',
              categoryKind: ProductCategory.furniture,
              subcategory: 'sub',
              priceAmount: 1000,
              stockQuantity: 5,
              mainImage: const ProductImageRef(path: 'x'),
              experienceType: ProductExperienceType.roomAr,
              deliveryEstimate: '3-5',
              addedDate: DateTime(2026, 1, 1),
              arMetadata: ProductArMetadata(
                storagePath: 'products/future-admin-product-42/ar/model-v1.glb',
                modelVersion: '1',
                sha256: 'a' * 64,
                widthM: 0.5,
                depthM: 0.5,
                heightM: 0.5,
              ),
            ),
          );

          final vm = build('future-admin-product-42');
          await settle();
          expect(vm.error, isNull);
          expect(vm.sessionArgs, isNotNull);
          final args = vm.sessionArgs!;
          expect(args.firestoreProductId, 'future-admin-product-42');
          expect(args.object, isNull);
          expect(args.nativeMode, 'future-admin-product-42');
        },
      );

      test(
        'a product whose arMetadata.storagePath belongs to a DIFFERENT '
        'product is rejected outright — never renders a cross-product model',
        () async {
          database.addProduct(
            ProductModel(
              id: 'sneaky-product',
              sku: 'SKU-SNEAKY',
              title: 'Sneaky Product',
              description: 'd',
              categoryId: 'furniture',
              categoryKind: ProductCategory.furniture,
              subcategory: 'sub',
              priceAmount: 1000,
              stockQuantity: 5,
              mainImage: const ProductImageRef(path: 'x'),
              experienceType: ProductExperienceType.roomAr,
              deliveryEstimate: '3-5',
              addedDate: DateTime(2026, 1, 1),
              arMetadata: const ProductArMetadata(
                // Belongs to a different product id — a migration bug or a
                // hand-edited Firestore doc, exactly what the defence-in-depth
                // check guards against.
                storagePath: 'products/luna-accent-chair/ar/model-v1.glb',
                modelVersion: '1',
                sha256:
                    'd67c68f823d06881ec1aabf7f8ca6f0128f1016483ea0307f5c2ecef66b3cf94',
                widthM: 0.70,
                depthM: 0.72,
                heightM: 0.82,
              ),
            ),
          );

          final vm = build('sneaky-product');
          await settle();
          // hasRenderableArModel is true (the contract itself is otherwise
          // valid) — but the session-args gate must still refuse it.
          expect(vm.product!.hasRenderableArModel, isTrue);
          expect(vm.sessionArgs, isNull);
          expect(vm.canStartAr, isFalse);
          expect(vm.canPreview, isFalse);
        },
      );
    });
  });
}
