import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/supabase.dart';
import '../models/product.dart';
import '../models/category.dart';
import '../models/brand.dart';
import '../models/review.dart';

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

  /// Visible reviews for a product, newest first. Reviewer identity is
  /// deliberately not fetched — see the Review model's doc comment.
  Future<List<Review>> fetchReviews(String productId) async {
    final rows = await supabase
        .from('reviews')
        .select()
        .eq('product_id', productId)
        .eq('is_visible', true)
        .order('created_at', ascending: false);
    return (rows as List).map((r) => Review.fromJson(r as Map<String, dynamic>)).toList();
  }

  /// The signed-in customer's own review of this product, if any — lets the
  /// UI switch between "Write a review" and "Edit your review".
  Future<Review?> fetchMyReview(String productId) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return null;
    final row = await supabase
        .from('reviews')
        .select()
        .eq('product_id', productId)
        .eq('customer_id', uid)
        .maybeSingle();
    return row == null ? null : Review.fromJson(row);
  }

  /// Whether the signed-in customer is eligible to review this product —
  /// true once they have a fulfilled order containing it. This mirrors the
  /// `reviews_owner_write` RLS policy (which enforces the real rule
  /// server-side); this check just lets the UI decide whether to show the
  /// "Write a review" button instead of surprising the customer with an
  /// insert that Postgres then rejects.
  Future<bool> canReviewProduct(String productId) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return false;
    final rows = await supabase
        .from('order_items')
        .select('order_id, orders!inner(customer_id, status)')
        .eq('product_id', productId)
        .eq('orders.customer_id', uid)
        .eq('orders.status', 'fulfilled')
        .limit(1);
    return (rows as List).isNotEmpty;
  }

  /// Creates or updates the signed-in customer's review for this product.
  /// `upsert` keeps this idempotent with the table's
  /// `unique (product_id, customer_id)` constraint, so re-submitting edits
  /// the existing review instead of failing.
  Future<void> submitReview(String productId, {required int rating, String? comment}) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) {
      throw Exception('Please log in to write a review.');
    }
    final trimmed = comment?.trim();
    await supabase.from('reviews').upsert(
      {
        'product_id': productId,
        'customer_id': uid,
        'rating': rating,
        'comment': (trimmed == null || trimmed.isEmpty) ? null : trimmed,
      },
      onConflict: 'product_id,customer_id',
    );
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

final productReviewsProvider = FutureProvider.family<List<Review>, String>((ref, productId) {
  return ref.watch(catalogServiceProvider).fetchReviews(productId);
});

final myReviewProvider = FutureProvider.family<Review?, String>((ref, productId) {
  return ref.watch(catalogServiceProvider).fetchMyReview(productId);
});

final canReviewProductProvider = FutureProvider.family<bool, String>((ref, productId) {
  return ref.watch(catalogServiceProvider).canReviewProduct(productId);
});
