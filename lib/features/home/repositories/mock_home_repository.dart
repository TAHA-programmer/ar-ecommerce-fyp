import '../../../../core/data/commerce_database.dart';
import '../../../../core/models/product/product_mappers.dart';
import '../models/category_model.dart';
import '../models/home_banner_model.dart';
import '../../../core/models/product/product_summary_model.dart';
import '../../../core/models/product/product_publication_status.dart';
import '../data/home_static_content.dart';
import 'home_repository.dart';

class MockHomeRepository implements HomeRepository {
  final CommerceDatabase _db;

  MockHomeRepository(this._db);

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
  Future<List<ProductSummaryModel>> getBestSellers() async {
    await Future.delayed(const Duration(milliseconds: 300));
    return _db.products
        .where(
          (p) =>
              p.isActive &&
              p.publicationStatus == ProductPublicationStatus.published &&
              p.popularityScore == 100 &&
              (p.id == 'luna-3-seater-sofa' ||
                  p.id == 'boho-woven-rug' ||
                  p.id == 'classic-blue-shirt'),
        )
        .map((p) => p.toSummaryModel())
        .toList();
  }

  @override
  Future<List<ProductSummaryModel>> getFeaturedProducts() async {
    await Future.delayed(const Duration(milliseconds: 300));
    return _db.products
        .where(
          (p) =>
              p.isActive &&
              p.publicationStatus == ProductPublicationStatus.published &&
              p.recommendationRank == 10,
        )
        .map((p) => p.toSummaryModel())
        .toList();
  }

  @override
  Future<List<ProductSummaryModel>> getNewArrivals() async {
    await Future.delayed(const Duration(milliseconds: 300));
    return _db.products
        .where(
          (p) =>
              p.isActive &&
              p.publicationStatus == ProductPublicationStatus.published &&
              p.recommendationRank == 20,
        )
        .map((p) => p.toSummaryModel())
        .toList();
  }

  @override
  Future<List<ProductSummaryModel>> getArEnabledProducts() async {
    await Future.delayed(const Duration(milliseconds: 300));
    return _db.products
        .where(
          (p) =>
              p.isActive &&
              p.publicationStatus == ProductPublicationStatus.published &&
              p.isRoomArEnabled &&
              (p.id == 'minimalist-bedroom-set' ||
                  p.id == 'wooden-console' ||
                  p.id == 'glass-coffee-table' ||
                  p.id == 'velvet-armchair'),
        )
        .map((p) => p.toSummaryModel())
        .toList();
  }

  @override
  Future<List<ProductSummaryModel>> getVirtualTryOnCollection() async {
    await Future.delayed(const Duration(milliseconds: 300));
    return _db.products
        .where(
          (p) =>
              p.isActive &&
              p.publicationStatus == ProductPublicationStatus.published &&
              p.isVirtualTryOnEnabled &&
              (p.id == 'floral-summer-dress' ||
                  p.id == 'casual-hoodie' ||
                  p.id == 'classic-blue-shirt' ||
                  p.id == 'autumn-outfit'),
        )
        .map((p) => p.toSummaryModel())
        .toList();
  }

  @override
  Future<List<ProductSummaryModel>> getPopularFurniture() async {
    await Future.delayed(const Duration(milliseconds: 300));
    return _db.products
        .where(
          (p) =>
              p.isActive &&
              p.publicationStatus == ProductPublicationStatus.published &&
              (p.id == 'marble-side-table' ||
                  p.id == 'velvet-armchair' ||
                  p.id == 'boho-woven-rug' ||
                  p.id == 'ceramic-vases-set'),
        )
        .map((p) => p.toSummaryModel())
        .toList();
  }

  @override
  Future<List<ProductSummaryModel>> getRecentlyViewed() async {
    await Future.delayed(const Duration(milliseconds: 300));
    return _db.products
        .where(
          (p) =>
              p.isActive &&
              p.publicationStatus == ProductPublicationStatus.published &&
              (p.id == 'velvet-armchair' ||
                  p.id == 'ceramic-vases-set' ||
                  p.id == 'classic-blue-shirt' ||
                  p.id == 'autumn-outfit'),
        )
        .map((p) => p.toSummaryModel())
        .toList();
  }

  @override
  Future<void> refresh() async {
    await Future.delayed(const Duration(milliseconds: 800));
  }
}
