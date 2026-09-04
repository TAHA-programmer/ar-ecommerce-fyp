// ignore_for_file: prefer_initializing_formals
import 'package:flutter/material.dart';
import '../../product_details/models/product_detail_model.dart';
import '../../product_details/repositories/product_details_repository.dart';
import '../../../core/models/product/product_experience_type.dart';
import '../models/virtual_try_on_camera_type.dart';

class VirtualTryOnSetupViewModel extends ChangeNotifier {
  final ProductDetailsRepository _repository;
  final String productId;

  bool isLoading = true;
  String? error;
  ProductDetailModel? product;
  VirtualTryOnCameraType selectedCamera = VirtualTryOnCameraType.front;

  VirtualTryOnSetupViewModel({
    required ProductDetailsRepository repository,
    required this.productId,
  }) : _repository = repository {
    _loadProduct();
  }

  Future<void> _loadProduct() async {
    try {
      isLoading = true;
      error = null;
      notifyListeners();

      product = await _repository.getProductDetails(productId);

      if (product?.experienceType != ProductExperienceType.virtualTryOn) {
        error = 'This product does not support Virtual Try-On.';
      }
    } catch (e) {
      error = 'Failed to load product details for Virtual Try-On.';
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  void selectCamera(VirtualTryOnCameraType camera) {
    if (selectedCamera != camera) {
      selectedCamera = camera;
      notifyListeners();
    }
  }
}
