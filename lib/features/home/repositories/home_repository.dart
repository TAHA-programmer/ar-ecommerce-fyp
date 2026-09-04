import '../models/category_model.dart';
import '../models/home_banner_model.dart';
import '../../../core/models/product/product_summary_model.dart';

abstract class HomeRepository {
  Future<List<HomeBannerModel>> getBanners();
  Future<List<CategoryModel>> getCategories();
  Future<List<ProductSummaryModel>> getBestSellers();
  Future<List<ProductSummaryModel>> getFeaturedProducts();
  Future<List<ProductSummaryModel>> getNewArrivals();
  Future<List<ProductSummaryModel>> getArEnabledProducts();
  Future<List<ProductSummaryModel>> getVirtualTryOnCollection();
  Future<List<ProductSummaryModel>> getPopularFurniture();
  Future<List<ProductSummaryModel>> getRecentlyViewed();
  Future<void> refresh();
}
