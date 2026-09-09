import '../models/category_model.dart';
import '../models/home_banner_model.dart';

/// Home's non-product data: the static hero banners and the real
/// Admin-managed categories collection.
///
/// Every Home **product** section is derived by [HomeViewModel] from the live
/// `CommerceDatabase` catalogue cache (+ the `productStats` / `recentlyViewed`
/// ordering signals) — Dynamic Home Content Stage 3. The old curated-ID /
/// `recommendationRank`-sentinel product methods were removed once no
/// consumer needed them (`20_DYNAMIC_HOME_CONTENT_PLAN.md` §9 Stage 3).
abstract class HomeRepository {
  Future<List<HomeBannerModel>> getBanners();
  Future<List<CategoryModel>> getCategories();
  Future<void> refresh();
}
