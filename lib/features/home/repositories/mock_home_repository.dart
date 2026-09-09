import '../models/category_model.dart';
import '../models/home_banner_model.dart';
import '../data/home_static_content.dart';
import 'home_repository.dart';

/// In-memory [HomeRepository] test/dev double: the static banners + the
/// static curated category list. Home's product sections are derived by
/// [HomeViewModel] from the `CommerceDatabase` cache, so this no longer
/// touches products at all.
class MockHomeRepository implements HomeRepository {
  MockHomeRepository();

  @override
  Future<List<HomeBannerModel>> getBanners() async {
    await Future.delayed(const Duration(milliseconds: 400));
    return homeStaticBanners;
  }

  @override
  Future<List<CategoryModel>> getCategories() async {
    await Future.delayed(const Duration(milliseconds: 300));
    return homeStaticCategories;
  }

  @override
  Future<void> refresh() async {
    await Future.delayed(const Duration(milliseconds: 800));
  }
}
