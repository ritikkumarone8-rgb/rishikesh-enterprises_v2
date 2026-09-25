/// A customer review of a product. Matches the `reviews` table (see
/// backend/sql/001_schema.sql) — writable only by the reviewing customer,
/// and only once they have a fulfilled order containing the product (see
/// the `reviews_owner_write` RLS policy). Reviewer identity is deliberately
/// not joined in here: RLS already hides other customers' profile rows from
/// a non-seller reader, so the UI shows reviews as from a "Verified buyer"
/// rather than surface a name it can't reliably read.
class Review {
  final String id;
  final String productId;
  final String customerId;
  final int rating;
  final String? comment;
  final DateTime createdAt;

  const Review({
    required this.id,
    required this.productId,
    required this.customerId,
    required this.rating,
    this.comment,
    required this.createdAt,
  });

  factory Review.fromJson(Map<String, dynamic> json) => Review(
        id: json['id'] as String,
        productId: json['product_id'] as String,
        customerId: json['customer_id'] as String,
        rating: (json['rating'] as num).toInt(),
        comment: json['comment'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}
