import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/core/data/mock_commerce_database.dart';
import 'package:twin_ar/features/product_details/repositories/mock_product_details_repository.dart';
import 'package:twin_ar/features/virtual_try_on/viewmodels/virtual_try_on_setup_viewmodel.dart';
import 'package:twin_ar/features/virtual_try_on/models/virtual_try_on_camera_type.dart';

void main() {
  late MockProductDetailsRepository repository;

  setUp(() {
    repository = MockProductDetailsRepository(
      MockCommerceDatabase(),
      simulateDelay: false,
    );
  });

  test('ViewModel initializes and loads valid male VTO product', () async {
    final viewModel = VirtualTryOnSetupViewModel(
      repository: repository,
      productId: 'mens-oxford-shirt',
    );

    expect(viewModel.isLoading, true);

    // Wait for mock data to load
    await Future.delayed(const Duration(milliseconds: 700));

    expect(viewModel.isLoading, false);
    expect(viewModel.error, isNull);
    expect(viewModel.product, isNotNull);
    expect(viewModel.product!.summary.title, 'Men\'s Oxford Shirt');
    expect(viewModel.selectedCamera, VirtualTryOnCameraType.front);
  });

  test('ViewModel initializes and loads valid female VTO product', () async {
    final viewModel = VirtualTryOnSetupViewModel(
      repository: repository,
      productId: 'womens-blazer',
    );

    await Future.delayed(const Duration(milliseconds: 700));

    expect(viewModel.isLoading, false);
    expect(viewModel.error, isNull);
    expect(viewModel.product, isNotNull);
    expect(viewModel.product!.summary.title, 'Women\'s Blazer');
  });

  test('ViewModel shows error for non-VTO product', () async {
    final viewModel = VirtualTryOnSetupViewModel(
      repository: repository,
      productId: 'luna-accent-chair',
    );

    await Future.delayed(const Duration(milliseconds: 700));

    expect(viewModel.isLoading, false);
    expect(viewModel.error, 'This product does not support Virtual Try-On.');
    expect(viewModel.product, isNotNull);
  });

  test('selectCamera updates state correctly', () async {
    final viewModel = VirtualTryOnSetupViewModel(
      repository: repository,
      productId: 'mens-oxford-shirt',
    );

    expect(viewModel.selectedCamera, VirtualTryOnCameraType.front);

    viewModel.selectCamera(VirtualTryOnCameraType.rear);
    expect(viewModel.selectedCamera, VirtualTryOnCameraType.rear);

    viewModel.selectCamera(VirtualTryOnCameraType.front);
    expect(viewModel.selectedCamera, VirtualTryOnCameraType.front);
  });
}
