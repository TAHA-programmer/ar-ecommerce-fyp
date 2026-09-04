import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/core/data/mock_commerce_database.dart';
import 'package:twin_ar/features/room_ar/capability/room_ar_capability.dart';
import 'package:twin_ar/features/room_ar/viewmodels/room_ar_preparation_viewmodel.dart';
import 'package:twin_ar/features/product_details/repositories/mock_product_details_repository.dart';

import '../capability/fake_capability_service.dart';

void main() {
  late MockProductDetailsRepository repository;

  setUp(() {
    repository = MockProductDetailsRepository(
      MockCommerceDatabase(),
      simulateDelay: false,
    );
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

    test(
      'approved product + camera device → Tier 2, correct session args',
      () async {
        final vm = build('luna-accent-chair');
        await settle();
        expect(vm.resolvedTier, RoomArTier.tier2Marker);
        expect(vm.canStartAr, isTrue);
        expect(vm.canPreview, isFalse);
        final args = vm.sessionArgs!;
        expect(args.object.firestoreProductId, 'luna-accent-chair');
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
        productId: 'velvet-armchair', // roomAr, no arMetadata
      );
      await settle();
      expect(vm.product, isNotNull);
      expect(vm.canStartAr, isFalse);
      expect(vm.canPreview, isFalse);
      expect(vm.deviceUnsupported, isFalse);
      expect(vm.sessionArgs, isNull);
      expect(fake.detectCalls, 0);
    });
  });
}
