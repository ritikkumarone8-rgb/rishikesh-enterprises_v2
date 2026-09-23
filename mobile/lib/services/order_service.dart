import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/supabase.dart';
import '../models/address.dart';
import '../models/order.dart';

class RazorpayOrderInfo {
  final String orderCode;
  final String rzpOrderId;
  final int amountPaise;
  final String currency;
  final String keyId;

  const RazorpayOrderInfo({
    required this.orderCode,
    required this.rzpOrderId,
    required this.amountPaise,
    required this.currency,
    required this.keyId,
  });

  factory RazorpayOrderInfo.fromJson(Map<String, dynamic> json) => RazorpayOrderInfo(
        orderCode: json['order_code'] as String,
        rzpOrderId: json['rzp_order_id'] as String,
        amountPaise: (json['amount'] as num).toInt(),
        currency: json['currency'] as String? ?? 'INR',
        keyId: json['key_id'] as String,
      );
}

/// Thrown for any expected, user-facing failure (out of stock, invalid
/// coupon, payment error, ...) so the UI can show `.message` directly
/// instead of a raw exception dump.
class OrderException implements Exception {
  final String message;
  const OrderException(this.message);
  @override
  String toString() => message;
}

class OrderService {
  Future<List<Address>> fetchAddresses() async {
    final rows = await supabase
        .from('addresses')
        .select()
        .order('is_default', ascending: false)
        .order('created_at', ascending: false);
    return (rows as List).map((r) => Address.fromJson(r as Map<String, dynamic>)).toList();
  }

  Future<Address> addAddress(Address address) async {
    final customerId = supabase.auth.currentUser?.id;
    if (customerId == null) throw const OrderException('Please log in to save an address.');
    final row = await supabase
        .from('addresses')
        .insert(address.toInsertJson(customerId))
        .select()
        .single();
    return Address.fromJson(row);
  }

  Future<void> deleteAddress(String id) => supabase.from('addresses').delete().eq('id', id);

  /// Places the order via the `create_order` Postgres RPC — see
  /// backend/sql/002_order_rpc.sql for why this one function is the ONLY
  /// path an order can be created through (server-recomputed pricing,
  /// atomic stock check-and-decrement, ownership-checked address).
  ///
  /// Returns the order_code. Any failure (out of stock, bad coupon,
  /// address mismatch, ...) surfaces as an [OrderException] with a
  /// friendly message lifted from the RPC's own error text.
  Future<Order> createOrder({
    required List<Map<String, dynamic>> items, // [{product_id, qty}]
    required String deliveryMode,
    String? addressId,
    String? couponCode,
    required String paymentMethod, // 'cod' | 'online'
  }) async {
    try {
      final row = await supabase.rpc('create_order', params: {
        'items': items,
        'p_delivery_mode': deliveryMode,
        'p_address_id': addressId,
        'p_coupon_code': couponCode,
        'p_payment_method': paymentMethod,
      });
      return Order.fromJson(row as Map<String, dynamic>);
    } catch (e) {
      throw OrderException(_friendlyRpcError(e.toString()));
    }
  }

  Future<RazorpayOrderInfo> createRazorpayOrder(String orderId) async {
    final res = await supabase.functions.invoke(
      'create-razorpay-order',
      body: {'order_id': orderId},
    );
    final data = res.data as Map<String, dynamic>;
    if (data['error'] != null) {
      throw OrderException(data['detail'] as String? ?? 'Could not start payment. Please try again.');
    }
    return RazorpayOrderInfo.fromJson(data);
  }

  Future<void> verifyPayment({
    required String orderId,
    required String rzpOrderId,
    required String rzpPaymentId,
    required String signature,
  }) async {
    final res = await supabase.functions.invoke(
      'verify-payment',
      body: {
        'order_id': orderId,
        'rzp_order_id': rzpOrderId,
        'rzp_payment_id': rzpPaymentId,
        'signature': signature,
      },
    );
    final data = res.data as Map<String, dynamic>;
    if (data['ok'] != true) {
      throw const OrderException(
        'Payment verification failed. If money was deducted, contact the store — do not pay again.',
      );
    }
  }

  Future<List<Order>> fetchMyOrders() async {
    final rows = await supabase
        .from('orders')
        .select('*, order_items(*)')
        .order('created_at', ascending: false);
    return (rows as List).map((r) => Order.fromJson(r as Map<String, dynamic>)).toList();
  }

  Future<Order?> fetchOrderByCode(String orderCode) async {
    final row = await supabase
        .from('orders')
        .select('*, order_items(*)')
        .eq('order_code', orderCode)
        .maybeSingle();
    if (row == null) return null;
    return Order.fromJson(row);
  }

  String _friendlyRpcError(String raw) {
    // Postgres RPC errors come back like "AUTH_REQUIRED: you must be..." —
    // strip the machine-readable code, keep the human message.
    final match = RegExp(r'[A-Z_]+:\s*(.+)').firstMatch(raw);
    return match?.group(1) ?? 'Could not place your order. Please try again.';
  }
}

final orderServiceProvider = Provider<OrderService>((ref) => OrderService());

final addressesProvider = FutureProvider<List<Address>>((ref) {
  return ref.watch(orderServiceProvider).fetchAddresses();
});

final myOrdersProvider = FutureProvider<List<Order>>((ref) {
  return ref.watch(orderServiceProvider).fetchMyOrders();
});

final orderByCodeProvider = FutureProvider.family<Order?, String>((ref, code) {
  return ref.watch(orderServiceProvider).fetchOrderByCode(code);
});
