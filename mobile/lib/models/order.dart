class OrderItem {
  final String id;
  final String? productId;
  final String productName;
  final String? brand;
  final double unitPrice;
  final int qty;
  final double lineTotal;
  final double discountAmount;
  final double finalAmount;

  const OrderItem({
    required this.id,
    this.productId,
    required this.productName,
    this.brand,
    required this.unitPrice,
    required this.qty,
    required this.lineTotal,
    required this.discountAmount,
    required this.finalAmount,
  });

  factory OrderItem.fromJson(Map<String, dynamic> json) => OrderItem(
        id: json['id'] as String,
        productId: json['product_id'] as String?,
        productName: json['product_name'] as String,
        brand: json['brand'] as String?,
        unitPrice: (json['unit_price'] as num).toDouble(),
        qty: (json['qty'] as num).toInt(),
        lineTotal: (json['line_total'] as num).toDouble(),
        discountAmount: (json['discount_amount'] as num?)?.toDouble() ?? 0,
        finalAmount: (json['final_amount'] as num).toDouble(),
      );
}

enum OrderStatus { newOrder, confirmed, inTransit, fulfilled, cancelled }
enum PaymentStatus { pending, paid, failed, cancelled }

OrderStatus orderStatusFromString(String s) => switch (s) {
      'confirmed' => OrderStatus.confirmed,
      'in_transit' => OrderStatus.inTransit,
      'fulfilled' => OrderStatus.fulfilled,
      'cancelled' => OrderStatus.cancelled,
      _ => OrderStatus.newOrder,
    };

PaymentStatus paymentStatusFromString(String s) => switch (s) {
      'paid' => PaymentStatus.paid,
      'failed' => PaymentStatus.failed,
      'cancelled' => PaymentStatus.cancelled,
      _ => PaymentStatus.pending,
    };

class Order {
  final String id;
  final String orderCode;
  final String deliveryMode; // 'delivery' | 'pickup'
  final Map<String, dynamic>? addressSnapshot;
  final String? couponCode;
  final double subtotal;
  final double discountTotal;
  final double codFee;
  final double grandTotal;
  final String paymentMethod; // 'online' | 'cod'
  final PaymentStatus paymentStatus;
  final OrderStatus status;
  final DateTime createdAt;
  final List<OrderItem> items;

  const Order({
    required this.id,
    required this.orderCode,
    required this.deliveryMode,
    this.addressSnapshot,
    this.couponCode,
    required this.subtotal,
    required this.discountTotal,
    required this.codFee,
    required this.grandTotal,
    required this.paymentMethod,
    required this.paymentStatus,
    required this.status,
    required this.createdAt,
    this.items = const [],
  });

  factory Order.fromJson(Map<String, dynamic> json) {
    final itemsJson = json['order_items'] as List<dynamic>? ?? const [];
    return Order(
      id: json['id'] as String,
      orderCode: json['order_code'] as String,
      deliveryMode: json['delivery_mode'] as String,
      addressSnapshot: json['address_snapshot'] as Map<String, dynamic>?,
      couponCode: json['coupon_code'] as String?,
      subtotal: (json['subtotal'] as num).toDouble(),
      discountTotal: (json['discount_total'] as num?)?.toDouble() ?? 0,
      codFee: (json['cod_fee'] as num?)?.toDouble() ?? 0,
      grandTotal: (json['grand_total'] as num).toDouble(),
      paymentMethod: json['payment_method'] as String,
      paymentStatus: paymentStatusFromString(json['payment_status'] as String? ?? 'pending'),
      status: orderStatusFromString(json['status'] as String? ?? 'new'),
      createdAt: DateTime.parse(json['created_at'] as String),
      items: itemsJson.map((e) => OrderItem.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }
}
