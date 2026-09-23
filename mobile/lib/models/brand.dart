class Brand {
  final String id;
  final String name;
  final String slug;
  final String? bannerUrl;
  final String? description;

  const Brand({
    required this.id,
    required this.name,
    required this.slug,
    this.bannerUrl,
    this.description,
  });

  factory Brand.fromJson(Map<String, dynamic> json) => Brand(
        id: json['id'] as String,
        name: json['name'] as String,
        slug: json['slug'] as String,
        bannerUrl: json['banner_url'] as String?,
        description: json['description'] as String?,
      );
}
