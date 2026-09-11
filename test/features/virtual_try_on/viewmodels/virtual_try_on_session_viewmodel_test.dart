import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:twin_ar/app/viewmodels/auth_session_state.dart';
import 'package:twin_ar/app/viewmodels/customer_shopping_state.dart';
import 'package:twin_ar/core/data/mock_cart_repository.dart';
import 'package:twin_ar/core/data/mock_favorites_repository.dart';
import 'package:twin_ar/core/models/auth/auth_result.dart';
import 'package:twin_ar/core/models/auth/user_role.dart';
import 'package:twin_ar/core/models/product/product_color_option.dart';
import 'package:twin_ar/core/models/product/product_size.dart';
import 'package:twin_ar/features/virtual_try_on/models/virtual_try_on_session_phase.dart';
import 'package:twin_ar/features/virtual_try_on/services/mock_virtual_try_on_photo_picker_service.dart';
import 'package:twin_ar/features/virtual_try_on/services/mock_virtual_try_on_service.dart';
import 'package:twin_ar/features/virtual_try_on/services/virtual_try_on_exception.dart';
import 'package:twin_ar/features/virtual_try_on/viewmodels/virtual_try_on_session_viewmodel.dart';

import '../virtual_try_on_test_helpers.dart';

Uint8List _validPhotoBytes() {
  final image = img.Image(width: 900, height: 1400);
  img.fill(image, color: img.ColorRgb8(100, 120, 140));
  return Uint8List.fromList(img.encodePng(image));
}

const _uid = 'test-uid-1';

AuthSessionState _signedInAuth() {
  final auth = AuthSessionState();
  auth.setSession(
    AuthResult.success(userId: _uid, email: 'a@b.com', role: UserRole.customer),
  );
  return auth;
}

CustomerShoppingState _shoppingState() =>
    CustomerShoppingState(MockFavoritesRepository(), MockCartRepository());

VirtualTryOnSessionViewModel _buildViewModel({
  MockVirtualTryOnService? service,
  MockVirtualTryOnPhotoPickerService? picker,
  AuthSessionState? auth,
  CustomerShoppingState? shoppingState,
  String colorKey = 'blue',
  String? size = 'm',
  String idempotencyKey = 'vto_initial_key',
}) {
  return VirtualTryOnSessionViewModel(
    repository: FakeVtoProductDetailsRepository(
      product: buildEligibleVtoProduct(),
      productId: kEligibleVtoProductId,
    ),
    service: service ?? MockVirtualTryOnService(),
    photoPicker: picker ?? MockVirtualTryOnPhotoPickerService(),
    shoppingState: shoppingState ?? _shoppingState(),
    authSessionState: auth ?? _signedInAuth(),
    productId: kEligibleVtoProductId,
    colorKey: colorKey,
    size: size,
    idempotencyKey: idempotencyKey,
  );
}

void main() {
  group('product loading', () {
    test('loads an eligible product', () async {
      final vm = _buildViewModel();
      expect(vm.isLoadingProduct, true);
      await Future.delayed(Duration.zero);
      expect(vm.isLoadingProduct, false);
      expect(vm.loadError, isNull);
      expect(vm.product, isNotNull);
    });

    test('sets loadError for an ineligible product', () async {
      final vm = VirtualTryOnSessionViewModel(
        repository: FakeVtoProductDetailsRepository(
          product: buildNonVtoProduct(),
          productId: 'non-vto-product',
        ),
        service: MockVirtualTryOnService(),
        photoPicker: MockVirtualTryOnPhotoPickerService(),
        shoppingState: _shoppingState(),
        authSessionState: _signedInAuth(),
        productId: 'non-vto-product',
        colorKey: 'blue',
        idempotencyKey: 'vto_x',
      );
      await Future.delayed(Duration.zero);
      expect(vm.loadError, "Virtual Try-On isn't available for this product.");
    });
  });

  group('photo acquisition', () {
    test('camera cancellation stays on capturePrompt with no error', () async {
      final picker = MockVirtualTryOnPhotoPickerService()
        ..nextCameraResult = null;
      final vm = _buildViewModel(picker: picker);
      await Future.delayed(Duration.zero);

      await vm.captureFromCamera();

      expect(vm.phase, VirtualTryOnSessionPhase.capturePrompt);
      expect(vm.photoRejectionMessage, isNull);
      expect(picker.captureFromCameraCalls, 1);
    });

    test('a valid captured photo moves to photoPreview', () async {
      final picker = MockVirtualTryOnPhotoPickerService()
        ..nextCameraResult = _validPhotoBytes();
      final vm = _buildViewModel(picker: picker);
      await Future.delayed(Duration.zero);

      await vm.captureFromCamera();

      expect(vm.phase, VirtualTryOnSessionPhase.photoPreview);
      expect(vm.previewBytes, isNotNull);
      // Re-encoded to real JPEG bytes regardless of the PNG source.
      expect(vm.previewBytes![0], 0xFF);
      expect(vm.previewBytes![1], 0xD8);
    });

    test('an invalid photo sets a rejection message and stays put', () async {
      final picker = MockVirtualTryOnPhotoPickerService()
        ..nextGalleryResult = Uint8List.fromList([1, 2, 3]);
      final vm = _buildViewModel(picker: picker);
      await Future.delayed(Duration.zero);

      await vm.pickFromGallery();

      expect(vm.phase, VirtualTryOnSessionPhase.capturePrompt);
      expect(vm.photoRejectionMessage, isNotNull);
    });

    test('discardPickedPhoto returns to capturePrompt', () async {
      final picker = MockVirtualTryOnPhotoPickerService()
        ..nextCameraResult = _validPhotoBytes();
      final vm = _buildViewModel(picker: picker);
      await Future.delayed(Duration.zero);
      await vm.captureFromCamera();
      expect(vm.phase, VirtualTryOnSessionPhase.photoPreview);

      vm.discardPickedPhoto();

      expect(vm.phase, VirtualTryOnSessionPhase.capturePrompt);
      expect(vm.previewBytes, isNull);
    });
  });

  group('generation happy path', () {
    test(
      'usePhotoAndGenerate goes uploading -> generating -> success',
      () async {
        final service = MockVirtualTryOnService();
        final picker = MockVirtualTryOnPhotoPickerService()
          ..nextCameraResult = _validPhotoBytes();
        final vm = _buildViewModel(service: service, picker: picker);
        await Future.delayed(Duration.zero);
        await vm.captureFromCamera();

        await vm.usePhotoAndGenerate();

        expect(vm.phase, VirtualTryOnSessionPhase.success);
        expect(vm.resultBytes, isNotNull);
        expect(vm.resultPath, isNotNull);
        expect(vm.resultExpiresAt, isNotNull);
        expect(service.uploadCalls, ['vto_initial_key']);
        expect(service.generateCalls, ['vto_initial_key']);
        expect(vm.isBusy, false);
      },
    );

    test('not signed in fails closed without calling the service', () async {
      final service = MockVirtualTryOnService();
      final picker = MockVirtualTryOnPhotoPickerService()
        ..nextCameraResult = _validPhotoBytes();
      final vm = _buildViewModel(
        service: service,
        picker: picker,
        auth: AuthSessionState(), // no session
      );
      await Future.delayed(Duration.zero);
      await vm.captureFromCamera();

      await vm.usePhotoAndGenerate();

      expect(vm.phase, VirtualTryOnSessionPhase.failed);
      expect(vm.lastError?.kind, VirtualTryOnErrorKind.notSignedIn);
      expect(service.uploadCalls, isEmpty);
    });
  });

  group('failure + retry', () {
    test(
      'a retryable failure keeps the photo and mints a new key on retry',
      () async {
        final service = MockVirtualTryOnService()
          ..nextGenerateError = const VirtualTryOnException(
            VirtualTryOnErrorKind.rateLimited,
            "You've reached the try-on limit for now. Please try again later.",
          );
        final picker = MockVirtualTryOnPhotoPickerService()
          ..nextCameraResult = _validPhotoBytes();
        final vm = _buildViewModel(service: service, picker: picker);
        await Future.delayed(Duration.zero);
        await vm.captureFromCamera();
        await vm.usePhotoAndGenerate();

        expect(vm.phase, VirtualTryOnSessionPhase.failed);
        expect(vm.lastError!.isRetryableWithSamePhoto, true);

        service.nextGenerateError = null; // the retry should now succeed
        await vm.retryAfterFailure();

        expect(vm.phase, VirtualTryOnSessionPhase.success);
        expect(service.generateCalls.length, 2);
        expect(
          service.generateCalls[0],
          isNot(equals(service.generateCalls[1])),
        );
      },
    );

    test('a photo-specific failure returns to capturePrompt on retry', () async {
      final service = MockVirtualTryOnService()
        ..nextGenerateError = const VirtualTryOnException(
          VirtualTryOnErrorKind.photoInvalid,
          "That photo couldn't be used. Please try a clear JPEG or PNG photo.",
        );
      final picker = MockVirtualTryOnPhotoPickerService()
        ..nextCameraResult = _validPhotoBytes();
      final vm = _buildViewModel(service: service, picker: picker);
      await Future.delayed(Duration.zero);
      await vm.captureFromCamera();
      await vm.usePhotoAndGenerate();
      expect(vm.phase, VirtualTryOnSessionPhase.failed);

      await vm.retryAfterFailure();

      expect(vm.phase, VirtualTryOnSessionPhase.capturePrompt);
      expect(vm.previewBytes, isNull);
      // No second generate call was made — the customer must pick a new photo.
      expect(service.generateCalls.length, 1);
    });
  });

  group('in-session colour/size change', () {
    test(
      'changing colour mints a fresh key and re-generates with the same photo',
      () async {
        final service = MockVirtualTryOnService();
        final picker = MockVirtualTryOnPhotoPickerService()
          ..nextCameraResult = _validPhotoBytes();
        final vm = _buildViewModel(service: service, picker: picker);
        await Future.delayed(Duration.zero);
        await vm.captureFromCamera();
        await vm.usePhotoAndGenerate();
        expect(vm.phase, VirtualTryOnSessionPhase.success);
        final firstKey = service.generateCalls.single;

        await vm.changeColor('black');

        expect(vm.currentColorKey, 'black');
        expect(vm.phase, VirtualTryOnSessionPhase.success);
        expect(service.generateCalls.length, 2);
        expect(service.generateCalls[1], isNot(equals(firstKey)));
        // Never re-picks a photo for a colour change.
        expect(picker.captureFromCameraCalls, 1);
      },
    );

    test('selecting the same colour again is a no-op', () async {
      final service = MockVirtualTryOnService();
      final picker = MockVirtualTryOnPhotoPickerService()
        ..nextCameraResult = _validPhotoBytes();
      final vm = _buildViewModel(
        service: service,
        picker: picker,
        colorKey: 'blue',
      );
      await Future.delayed(Duration.zero);
      await vm.captureFromCamera();
      await vm.usePhotoAndGenerate();

      await vm.changeColor('blue');

      expect(service.generateCalls.length, 1);
    });

    test(
      'changing only size never calls generate again and flags the notice',
      () async {
        final service = MockVirtualTryOnService();
        final picker = MockVirtualTryOnPhotoPickerService()
          ..nextCameraResult = _validPhotoBytes();
        final vm = _buildViewModel(service: service, picker: picker, size: 's');
        await Future.delayed(Duration.zero);
        await vm.captureFromCamera();
        await vm.usePhotoAndGenerate();
        expect(vm.sizeOnlyChangedNotice, false);

        vm.changeSize('l');

        expect(vm.currentSize, 'l');
        expect(vm.sizeOnlyChangedNotice, true);
        expect(service.generateCalls.length, 1);
        expect(vm.phase, VirtualTryOnSessionPhase.success);
      },
    );
  });

  group('cancellation', () {
    test(
      'cancelDuringUpload deletes the upload and returns to photoPreview, ignoring the stale upload completion',
      () async {
        final service = MockVirtualTryOnService()
          ..uploadGate = Completer<void>();
        final picker = MockVirtualTryOnPhotoPickerService()
          ..nextCameraResult = _validPhotoBytes();
        final vm = _buildViewModel(service: service, picker: picker);
        await Future.delayed(Duration.zero);
        await vm.captureFromCamera();

        final generateFuture = vm.usePhotoAndGenerate();
        await Future.delayed(Duration.zero); // let it reach "uploading"
        expect(vm.phase, VirtualTryOnSessionPhase.uploading);

        await vm.cancelDuringUpload();

        expect(vm.phase, VirtualTryOnSessionPhase.photoPreview);
        expect(vm.isBusy, false);
        expect(service.deletedUploadSessionIds, isNotEmpty);

        // Now let the original (stale) upload call finally resolve - it must
        // NOT resurrect the old generation and overwrite the cancelled state.
        service.uploadGate!.complete();
        await generateFuture;
        await Future.delayed(Duration.zero);

        expect(vm.phase, VirtualTryOnSessionPhase.photoPreview);
        expect(service.generateCalls, isEmpty);
      },
    );
  });

  group('delete preview / leave flow', () {
    test(
      'deletePreviewAndReset deletes the result and resets to capturePrompt',
      () async {
        final service = MockVirtualTryOnService();
        final picker = MockVirtualTryOnPhotoPickerService()
          ..nextCameraResult = _validPhotoBytes();
        final vm = _buildViewModel(service: service, picker: picker);
        await Future.delayed(Duration.zero);
        await vm.captureFromCamera();
        await vm.usePhotoAndGenerate();
        final path = vm.resultPath!;

        await vm.deletePreviewAndReset();

        expect(service.deletedResultPaths, [path]);
        expect(vm.phase, VirtualTryOnSessionPhase.capturePrompt);
        expect(vm.resultBytes, isNull);
      },
    );

    test(
      'deleteResultOnLeave deletes the result without resetting phase',
      () async {
        final service = MockVirtualTryOnService();
        final picker = MockVirtualTryOnPhotoPickerService()
          ..nextCameraResult = _validPhotoBytes();
        final vm = _buildViewModel(service: service, picker: picker);
        await Future.delayed(Duration.zero);
        await vm.captureFromCamera();
        await vm.usePhotoAndGenerate();
        final path = vm.resultPath!;

        await vm.deleteResultOnLeave();

        expect(service.deletedResultPaths, [path]);
      },
    );

    test('deleteResultOnLeave is a no-op with no result', () async {
      final service = MockVirtualTryOnService();
      final vm = _buildViewModel(service: service);
      await Future.delayed(Duration.zero);

      await vm.deleteResultOnLeave();

      expect(service.deletedResultPaths, isEmpty);
    });
  });

  group('add to cart', () {
    test('adds the exact selected variant with quantity 1', () async {
      final service = MockVirtualTryOnService();
      final picker = MockVirtualTryOnPhotoPickerService()
        ..nextCameraResult = _validPhotoBytes();
      final shoppingState = _shoppingState();
      final vm = _buildViewModel(
        service: service,
        picker: picker,
        shoppingState: shoppingState,
        colorKey: 'black',
        size: 'l',
      );
      await Future.delayed(Duration.zero);
      await vm.captureFromCamera();
      await vm.usePhotoAndGenerate();

      final error = await vm.addSelectedVariantToCart();

      expect(error, isNull);
      expect(shoppingState.cartItems.length, 1);
      final item = shoppingState.cartItems.single;
      expect(item.productId, kEligibleVtoProductId);
      expect(item.selectedColor, ProductColorOption.black);
      expect(item.selectedSize, ProductSize.l);
      expect(item.quantity, 1);
    });

    test('uses the LATEST colour/size even after a size-only change', () async {
      final service = MockVirtualTryOnService();
      final picker = MockVirtualTryOnPhotoPickerService()
        ..nextCameraResult = _validPhotoBytes();
      final shoppingState = _shoppingState();
      final vm = _buildViewModel(
        service: service,
        picker: picker,
        shoppingState: shoppingState,
        size: 's',
      );
      await Future.delayed(Duration.zero);
      await vm.captureFromCamera();
      await vm.usePhotoAndGenerate();
      vm.changeSize('xl');

      await vm.addSelectedVariantToCart();

      expect(shoppingState.cartItems.single.selectedSize, ProductSize.xl);
    });
  });

  group('duplicate-tap protection', () {
    test('usePhotoAndGenerate is a no-op while already busy', () async {
      final service = MockVirtualTryOnService()..uploadGate = Completer<void>();
      final picker = MockVirtualTryOnPhotoPickerService()
        ..nextCameraResult = _validPhotoBytes();
      final vm = _buildViewModel(service: service, picker: picker);
      await Future.delayed(Duration.zero);
      await vm.captureFromCamera();

      final first = vm.usePhotoAndGenerate();
      await Future.delayed(Duration.zero);
      expect(vm.isBusy, true);

      await vm.usePhotoAndGenerate(); // second tap while busy
      expect(service.uploadCalls.length, 1);

      service.uploadGate!.complete();
      await first;
    });
  });

  group('stale result cleanup (Phase 9.3 Stage 5 hardening)', () {
    test(
      'changing colour after a success deletes the PREVIOUS colour\'s result',
      () async {
        final service = MockVirtualTryOnService();
        final picker = MockVirtualTryOnPhotoPickerService()
          ..nextCameraResult = _validPhotoBytes();
        final vm = _buildViewModel(
          service: service,
          picker: picker,
          colorKey: 'blue',
        );
        await Future.delayed(Duration.zero);
        await vm.captureFromCamera();
        await vm.usePhotoAndGenerate();
        final firstResultPath = vm.resultPath!;

        await vm.changeColor('black');

        expect(service.deletedResultPaths, contains(firstResultPath));
        // The new (second) result path must NOT itself be immediately
        // deleted - only the superseded one.
        expect(vm.resultPath, isNot(equals(firstResultPath)));
        expect(service.deletedResultPaths, isNot(contains(vm.resultPath)));
      },
    );

    test('startRetake deletes the result it is abandoning', () async {
      final service = MockVirtualTryOnService();
      final picker = MockVirtualTryOnPhotoPickerService()
        ..nextCameraResult = _validPhotoBytes();
      final vm = _buildViewModel(service: service, picker: picker);
      await Future.delayed(Duration.zero);
      await vm.captureFromCamera();
      await vm.usePhotoAndGenerate();
      final path = vm.resultPath!;

      vm.startRetake();
      await Future.delayed(Duration.zero); // fire-and-forget delete completes

      expect(service.deletedResultPaths, contains(path));
      expect(vm.resultPath, isNull);
      expect(vm.phase, VirtualTryOnSessionPhase.capturePrompt);
    });

    test('a colour change that then FAILS still deletes the abandoned prior '
        'success (never silently orphaned)', () async {
      final service = MockVirtualTryOnService();
      final picker = MockVirtualTryOnPhotoPickerService()
        ..nextCameraResult = _validPhotoBytes();
      final vm = _buildViewModel(
        service: service,
        picker: picker,
        colorKey: 'blue',
      );
      await Future.delayed(Duration.zero);
      await vm.captureFromCamera();
      await vm.usePhotoAndGenerate();
      final firstResultPath = vm.resultPath!;

      service.nextGenerateError = const VirtualTryOnException(
        VirtualTryOnErrorKind.rateLimited,
        "You've reached the try-on limit for now. Please try again later.",
      );
      await vm.changeColor('black');

      expect(vm.phase, VirtualTryOnSessionPhase.failed);
      expect(service.deletedResultPaths, contains(firstResultPath));
      // The failed attempt must not resurrect the old result reference.
      expect(vm.resultPath, isNull);
    });

    test('retrying after a later failure still does not leak an earlier '
        'success left behind in resultPath', () async {
      final service = MockVirtualTryOnService();
      final picker = MockVirtualTryOnPhotoPickerService()
        ..nextCameraResult = _validPhotoBytes();
      final vm = _buildViewModel(service: service, picker: picker);
      await Future.delayed(Duration.zero);
      await vm.captureFromCamera();
      await vm.usePhotoAndGenerate();
      final firstResultPath = vm.resultPath!;

      // Change colour, but this attempt fails - resultPath is already
      // cleared (and the old one deleted) by the fix, so nothing further
      // to leak here; retrying now should succeed cleanly.
      service.nextGenerateError = const VirtualTryOnException(
        VirtualTryOnErrorKind.timeout,
        'Generating your preview took too long. Please try again.',
      );
      await vm.changeColor('black');
      expect(vm.phase, VirtualTryOnSessionPhase.failed);

      service.nextGenerateError = null;
      await vm.retryAfterFailure();

      expect(vm.phase, VirtualTryOnSessionPhase.success);
      // Only the very first result was ever deleted - the retry's own
      // fresh success was never itself deleted.
      expect(service.deletedResultPaths, [firstResultPath]);
    });

    test(
      'a genuinely new first-ever generation never calls deleteResultBestEffort',
      () async {
        final service = MockVirtualTryOnService();
        final picker = MockVirtualTryOnPhotoPickerService()
          ..nextCameraResult = _validPhotoBytes();
        final vm = _buildViewModel(service: service, picker: picker);
        await Future.delayed(Duration.zero);
        await vm.captureFromCamera();

        await vm.usePhotoAndGenerate();

        expect(vm.phase, VirtualTryOnSessionPhase.success);
        expect(service.deletedResultPaths, isEmpty);
      },
    );
  });
}
