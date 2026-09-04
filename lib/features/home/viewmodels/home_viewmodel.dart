import 'package:flutter/foundation.dart';
import '../../../core/data/commerce_database.dart';
import '../../../app/viewmodels/customer_shopping_state.dart';
import '../models/category_model.dart';
import '../models/home_banner_model.dart';
import '../../../core/models/product/product_summary_model.dart';
import '../repositories/home_repository.dart';
import '../../product_details/repositories/product_details_repository.dart';

class HomeViewModel extends ChangeNotifier {
  final HomeRepository _repository;
  final ProductDetailsRepository _productDetailsRepository;
  final CustomerShoppingState _shoppingState;
  final CommerceDatabase _db;

  HomeViewModel(
    this._repository,
    this._productDetailsRepository,
    this._shoppingState,
    this._db,
  ) {
    _shoppingState.addListener(_onShoppingStateChanged);
    _db.addListener(_onDbChanged);
  }

  void _onShoppingStateChanged() {
    notifyListeners();
  }

  void _onDbChanged() {
    _hasLoaded = false;
    loadHomeData();
  }

  @override
  void dispose() {
    _shoppingState.removeListener(_onShoppingStateChanged);
    _db.removeListener(_onDbChanged);
    super.dispose();
  }

  bool _isLoading = true;
  bool get isLoading => _isLoading;

  List<HomeBannerModel> _banners = [];
  List<HomeBannerModel> get banners => _banners;

  List<CategoryModel> _categories = [];
  List<CategoryModel> get categories => _categories;

  List<ProductSummaryModel> _bestSellers = [];
  List<ProductSummaryModel> get bestSellers => _bestSellers;

  List<ProductSummaryModel> _featuredProducts = [];
  List<ProductSummaryModel> get featuredProducts => _featuredProducts;

  List<ProductSummaryModel> _newArrivals = [];
  List<ProductSummaryModel> get newArrivals => _newArrivals;

  List<ProductSummaryModel> _arEnabledProducts = [];
  List<ProductSummaryModel> get arEnabledProducts => _arEnabledProducts;

  List<ProductSummaryModel> _virtualTryOnCollection = [];
  List<ProductSummaryModel> get virtualTryOnCollection =>
      _virtualTryOnCollection;

  List<ProductSummaryModel> _popularFurniture = [];
  List<ProductSummaryModel> get popularFurniture => _popularFurniture;

  List<ProductSummaryModel> _recentlyViewed = [];
  List<ProductSummaryModel> get recentlyViewed => _recentlyViewed;

  int get cartCount => _shoppingState.cartCount;

  bool isFavorite(String productId) => _shoppingState.isFavorite(productId);

  /// Returns `null` on success or a clean, `AppToast`-ready error message.
  Future<String?> toggleFavorite(String productId) =>
      _shoppingState.toggleFavorite(productId);

  Future<String?> addToCart(String productId) async {
    try {
      final details = await _productDetailsRepository.getProductDetails(
        productId,
      );
      final defaultColor =
          details.defaultColor ??
          (details.availableColors.isNotEmpty
              ? details.availableColors.first
              : null);
      final defaultSize =
          details.defaultSize ??
          (details.availableSizes.isNotEmpty
              ? details.availableSizes.first
              : null);

      return await _shoppingState.addToCart(
        productId,
        selectedColor: defaultColor,
        selectedSize: defaultSize,
        priceAmountSnapshot: _extractPriceAmount(details.summary.currentPrice),
      );
    } catch (e) {
      // Fallback
      return await _shoppingState.addToCart(productId);
    }
  }

  int _extractPriceAmount(String currentPrice) {
    final rawString = currentPrice.replaceAll(RegExp(r'[^0-9]'), '');
    return int.tryParse(rawString) ?? 0;
  }

  bool _hasLoaded = false;

  Future<void> loadHomeData() async {
    if (_hasLoaded) return;
    _isLoading = true;
    notifyListeners();

    try {
      final results = await Future.wait([
        _repository.getBanners(),
        _repository.getCategories(),
        _repository.getBestSellers(),
        _repository.getFeaturedProducts(),
        _repository.getNewArrivals(),
        _repository.getArEnabledProducts(),
        _repository.getVirtualTryOnCollection(),
        _repository.getPopularFurniture(),
        _repository.getRecentlyViewed(),
      ]);

      _banners = results[0] as List<HomeBannerModel>;
      _categories = results[1] as List<CategoryModel>;
      _bestSellers = results[2] as List<ProductSummaryModel>;
      _featuredProducts = results[3] as List<ProductSummaryModel>;
      _newArrivals = results[4] as List<ProductSummaryModel>;
      _arEnabledProducts = results[5] as List<ProductSummaryModel>;
      _virtualTryOnCollection = results[6] as List<ProductSummaryModel>;
      _popularFurniture = results[7] as List<ProductSummaryModel>;
      _recentlyViewed = results[8] as List<ProductSummaryModel>;
    } catch (e) {
      // Print error in debug mode for now
      debugPrint('Failed to load home data: $e');
    } finally {
      _hasLoaded = true;
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    try {
      await _repository.refresh();
      final results = await Future.wait([
        _repository.getBanners(),
        _repository.getCategories(),
        _repository.getBestSellers(),
        _repository.getFeaturedProducts(),
        _repository.getNewArrivals(),
        _repository.getArEnabledProducts(),
        _repository.getVirtualTryOnCollection(),
        _repository.getPopularFurniture(),
        _repository.getRecentlyViewed(),
      ]);

      _banners = results[0] as List<HomeBannerModel>;
      _categories = results[1] as List<CategoryModel>;
      _bestSellers = results[2] as List<ProductSummaryModel>;
      _featuredProducts = results[3] as List<ProductSummaryModel>;
      _newArrivals = results[4] as List<ProductSummaryModel>;
      _arEnabledProducts = results[5] as List<ProductSummaryModel>;
      _virtualTryOnCollection = results[6] as List<ProductSummaryModel>;
      _popularFurniture = results[7] as List<ProductSummaryModel>;
      _recentlyViewed = results[8] as List<ProductSummaryModel>;
      notifyListeners();
    } catch (e) {
      debugPrint('Failed to refresh home data: $e');
      // Do not clear existing data on error
    }
  }
}
