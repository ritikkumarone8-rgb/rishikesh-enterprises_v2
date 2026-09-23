class ProductImage {
  final String id;
  final String url;
  final int sortOrder;

  const ProductImage({required this.id, required this.url, required this.sortOrder});

  factory ProductImage.fromJson(Map<String, dynamic> json) => ProductImage(
        id: json['id'] as String,
        url: json['url'] as String,
        sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
      );
}

class Product {
  final String id;
  final String name;
  final String? brandId;
  final String? brandName;
  final String? categoryId;
  final double price;
  final double? mrp;
  final int stock;
  final String? description;
  final bool isPopular;
  final bool couponEligible;
  final double avgRating;
  final int ratingCount;
  final List<ProductImage> images;

  const Product({
    required this.id,
    required this.name,
    this.brandId,
    this.brandName,
    this.categoryId,
    required this.price,
    this.mrp,
    required this.stock,
    this.description,
    this.isPopular = false,
    this.couponEligible = true,
    this.avgRating = 0,
    this.ratingCount = 0,
    this.images = const [],
  });

  /// First image (by sort_order) or null if the seller hasn't added any yet —
  /// callers should fall back to a placeholder illustration, never a broken link.
  String? get coverImageUrl => images.isNotEmpty ? images.first.url : null;

  int? get discountPercent {
    if (mrp == null || mrp! <= price) return null;
    return (100 - (price / mrp! * 100)).round();
  }

  bool get inStock => stock > 0;
  bool get isLowStock => stock > 0 && stock <= 5;

  factory Product.fromJson(Map<String, dynamic> json) {
    final imagesJson = json['product_images'] as List<dynamic>? ?? const [];
    final images = imagesJson
        .map((e) => ProductImage.fromJson(e as Map<String, dynamic>))
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return Product(
      id: json['id'] as String,
      name: json['name'] as String,
      brandId: json['brand_id'] as String?,
      brandName: json['brand_name'] as String?,
      categoryId: json['category_id'] as String?,
      price: (json['price'] as num).toDouble(),
      mrp: (json['mrp'] as num?)?.toDouble(),
      stock: (json['stock'] as num?)?.toInt() ?? 0,
      description: json['description'] as String?,
      isPopular: json['is_popular'] as bool? ?? false,
      couponEligible: json['coupon_eligible'] as bool? ?? true,
      avgRating: (json['avg_rating'] as num?)?.toDouble() ?? 0,
      ratingCount: (json['rating_count'] as num?)?.toInt() ?? 0,
      images: images,
    );
  }
}
