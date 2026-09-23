import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/cart_item.dart';
import '../models/product.dart';
import 'catalog_service.dart';

const _cartPrefsKey = 're_cart_v1';

class CartNotifier extends StateNotifier<List<CartItem>> {
  final CatalogService _catalog;
  CartNotifier(this._catalog) : super(const []) {
    _restore();
  }

  int get totalQty => state.fold(0, (sum, item) => sum + item.qty);
  double get subtotal => state.fold(0.0, (sum, item) => sum + item.lineTotal);

  int qtyOf(String productId) {
    final match = state.where((i) => i.product.id == productId);
    return match.isEmpty ? 0 : match.first.qty;
  }

  /// Adds one unit, refusing to exceed the product's real stock — this is
  /// the fix for the old site's bug where the "+" stepper never checked
  /// stock once an item was already in the cart.
  String? add(Product product) {
    final existingIndex = state.indexWhere((i) => i.product.id == product.id);
    if (existingIndex == -1) {
      if (product.stock <= 0) return 'Sorry, this item is out of stock.';
      state = [...state, CartItem(product: product, qty: 1)];
      _persist();
      return null;
    }
    final existing = state[existingIndex];
    if (existing.qty >= product.stock) {
      return 'Only ${product.stock} in stock — that\'s all we have right now.';
    }
    _updateAt(existingIndex, existing.copyWith(qty: existing.qty + 1));
    return null;
  }

  String? increment(String productId) {
    final i = state.indexWhere((c) => c.product.id == productId);
    if (i == -1) return null;
    final item = state[i];
    if (item.qty >= item.product.stock) {
      return 'Only ${item.product.stock} in stock — that\'s all we have right now.';
    }
    _updateAt(i, item.copyWith(qty: item.qty + 1));
    return null;
  }

  void decrement(String productId) {
    final i = state.indexWhere((c) => c.product.id == productId);
    if (i == -1) return;
    final item = state[i];
    if (item.qty <= 1) {
      remove(productId);
    } else {
      _updateAt(i, item.copyWith(qty: item.qty - 1));
    }
  }

  void remove(String productId) {
    state = state.where((c) => c.product.id != productId).toList();
    _persist();
  }

  void clear() {
    state = const [];
    _persist();
  }

  /// Re-fetches every cart line's product fresh from the server. Call this
  /// right before showing checkout totals or placing an order, so a stale
  /// cached price/stock never makes it into what the customer is charged —
  /// the server (`create_order` RPC) recomputes everything anyway, but this
  /// keeps what the customer *sees* accurate too, and drops any item that
  /// went inactive/out of stock since it was added, with a clear reason.
  Future<List<String>> refreshFromServer() async {
    final notes = <String>[];
    final next = <CartItem>[];
    for (final item in state) {
      final fresh = await _catalog.fetchProductById(item.product.id);
      if (fresh == null || !fresh.inStock) {
        notes.add('${item.product.name} is no longer available and was removed from your cart.');
        continue;
      }
      final qty = item.qty > fresh.stock ? fresh.stock : item.qty;
      if (qty < item.qty) {
        notes.add('Only $qty of ${fresh.name} left — updated the quantity in your cart.');
      }
      next.add(CartItem(product: fresh, qty: qty));
    }
    state = next;
    _persist();
    return notes;
  }

  void _updateAt(int index, CartItem updated) {
    final next = [...state];
    next[index] = updated;
    state = next;
    _persist();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = state.map((c) => {'id': c.product.id, 'qty': c.qty}).toList();
    await prefs.setString(_cartPrefsKey, jsonEncode(raw));
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cartPrefsKey);
      if (raw == null) return;
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      final items = <CartItem>[];
      for (final entry in list) {
        final product = await _catalog.fetchProductById(entry['id'] as String);
        if (product == null || !product.inStock) continue;
        final qty = (entry['qty'] as num).toInt().clamp(1, product.stock);
        items.add(CartItem(product: product, qty: qty));
      }
      state = items;
    } catch (_) {
      // corrupt/old cart data — start fresh rather than crash the app
      state = const [];
    }
  }
}

final cartProvider = StateNotifierProvider<CartNotifier, List<CartItem>>((ref) {
  return CartNotifier(ref.watch(catalogServiceProvider));
});

// NOTE: these watch `cartProvider` itself (the state), not `.notifier` —
// watching `.notifier` would NOT rebuild when the cart contents change,
// only when the notifier instance is (re)created, which is a classic
// Riverpod footgun.
final cartTotalQtyProvider = Provider<int>((ref) {
  final items = ref.watch(cartProvider);
  return items.fold(0, (sum, item) => sum + item.qty);
});

final cartSubtotalProvider = Provider<double>((ref) {
  final items = ref.watch(cartProvider);
  return items.fold(0.0, (sum, item) => sum + item.lineTotal);
});
