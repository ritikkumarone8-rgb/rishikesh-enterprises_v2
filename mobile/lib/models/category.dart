class Category {
  final String id;
  final String slug;
  final String name;
  final String? imageUrl;
  final int sortOrder;

  const Category({
    required this.id,
    required this.slug,
    required this.name,
    this.imageUrl,
    this.sortOrder = 0,
  });

  factory Category.fromJson(Map<String, dynamic> json) => Category(
        id: json['id'] as String,
        slug: json['slug'] as String,
        name: json['name'] as String,
        imageUrl: json['image_url'] as String?,
        sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
      );
}
