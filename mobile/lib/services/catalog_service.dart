import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/supabase.dart';
import '../models/product.dart';
import '../models/category.dart';
import '../models/brand.dart';

class Deal {
  final String id;
  final String title;
  final String? description;
  final String? categoryId;
  final String? img;

  const Deal({required this.id, required this.title, this.description, this.categoryId, this.img});

  factory Deal.fromJson(Map<String, dynamic> json) => Deal(
        id: json['id'] as String,
        title: json['title'] as String,
        description: json['description'] as String?,
        categoryId: json['category_id'] as String?,
        img: json['img'] as String?,
      );
}

class CatalogService {
  static const _productSelect = '*, product_images(*)';

  Future<List<Category>> fetchCategories() async {
    final rows = await supabase
        .from('categories')
        .select()
        .eq('is_active', true)
        .order('sort_order');
    return (rows as List).map((r) => Category.fromJson(r as Map<String, dynamic>)).toList();
  }

  Future<List<Brand>> fetchBrands() async {
    final rows = await supabase
        .from('brands')
        .select()
        .eq('is_active', true)
        .order('sort_order');
    return (rows as List).map((r) => Brand.fromJson(r as Map<String, dynamic>)).toList();
  }

  Future<List<Deal>> fetchDeals() async {
    final rows = await supabase.from('deals').select().eq('is_active', true);
    return (rows as List).map((r) => Deal.fromJson(r as Map<String, dynamic>)).toList();
  }

  Future<List<Product>> fetchPopularProducts({int limit = 12}) async {
    final rows = await supabase
        .from('products')
        .select(_productSelect)
        .eq('is_active', true)
        .eq('is_popular', true)
        .order('created_at', ascending: false)
        .limit(limit);
    return (rows as List).map((r) => Product.fromJson(r as Map<String, dynamic>)).toList();
  }

  Future<List<Product>> fetchByCategory(String categoryId, {int limit = 60}) async {
    final rows = await supabase
        .from('products')
        .select(_productSelect)
        .eq('is_active', true)
        .eq('category_id', categoryId)
        .order('created_at', ascending: false)
        .limit(limit);
    return (rows as List).map((r) => Product.fromJson(r as Map<String, dynamic>)).toList();
  }

  Future<List<Product>> fetchByBrand(String brandId, {int limit = 60}) async {
    final rows = await supabase
        .from('products')
        .select(_productSelect)
        .eq('is_active', true)
        .eq('brand_id', brandId)
        .order('created_at', ascending: false)
        .limit(limit);
    return (rows as List).map((r) => Product.fromJson(r as Map<String, dynamic>)).toList();
  }

  Future<Product?> fetchProductById(String id) async {
    final row = await supabase
        .from('products')
        .select(_productSelect)
        .eq('id', id)
        .maybeSingle();
    if (row == null) return null;
    return Product.fromJson(row);
  }

  /// Server-side search: full-text ranking first, typo-tolerant trigram
  /// fallback second (see `search_products` in the SQL migrations) — so
  /// "buld" still finds "Bulb" and "celing fan" still finds "Ceiling Fan".
  /// The RPC returns bare product rows (no nested images), so we fetch
  /// images for the result set in one follow-up query and stitch them in.
  Future<List<Product>> search(String query, {String? categoryId, int limit = 30}) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];

    final rows = await supabase.rpc('search_products', params: {
      'q': trimmed,
      'cat_id': categoryId,
      'limit_n': limit,
      'offset_n': 0,
    });
    final list = (rows as List).cast<Map<String, dynamic>>();
    if (list.isEmpty) return [];

    final ids = list.map((r) => r['id'] as String).toList();
    final imageRows = await supabase
        .from('product_images')
        .select()
        .inFilter('product_id', ids)
        .order('sort_order');
    final imagesByProduct = <String, List<Map<String, dynamic>>>{};
    for (final img in (imageRows as List).cast<Map<String, dynamic>>()) {
      imagesByProduct.putIfAbsent(img['product_id'] as String, () => []).add(img);
    }

    return list.map((r) {
      final withImages = {...r, 'product_images': imagesByProduct[r['id']] ?? const []};
      return Product.fromJson(withImages);
    }).toList();
  }
}

final catalogServiceProvider = Provider<CatalogService>((ref) => CatalogService());

final categoriesProvider = FutureProvider<List<Category>>((ref) {
  return ref.watch(catalogServiceProvider).fetchCategories();
});

final brandsProvider = FutureProvider<List<Brand>>((ref) {
  return ref.watch(catalogServiceProvider).fetchBrands();
});

final dealsProvider = FutureProvider<List<Deal>>((ref) {
  return ref.watch(catalogServiceProvider).fetchDeals();
});

final popularProductsProvider = FutureProvider<List<Product>>((ref) {
  return ref.watch(catalogServiceProvider).fetchPopularProducts();
});

final categoryProductsProvider =
    FutureProvider.family<List<Product>, String>((ref, categoryId) {
  return ref.watch(catalogServiceProvider).fetchByCategory(categoryId);
});

final brandProductsProvider = FutureProvider.family<List<Product>, String>((ref, brandId) {
  return ref.watch(catalogServiceProvider).fetchByBrand(brandId);
});

final productDetailProvider = FutureProvider.family<Product?, String>((ref, productId) {
  return ref.watch(catalogServiceProvider).fetchProductById(productId);
});

final searchResultsProvider =
    FutureProvider.family<List<Product>, String>((ref, query) {
  return ref.watch(catalogServiceProvider).search(query);
});
