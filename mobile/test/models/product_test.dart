import 'package:flutter_test/flutter_test.dart';
import 'package:rishikesh_enterprises/models/product.dart';
import 'package:rishikesh_enterprises/models/address.dart';
import 'package:rishikesh_enterprises/models/order.dart';

// Pure-logic unit tests for the model helpers that drive pricing/stock
// badges across the app (ProductCard, product detail, cart). These run
// with plain `flutter test` — no Supabase/network needed — so CI can catch
// a regression here (e.g. a bad discount-percent calculation, or a stock
// threshold typo) before it ships.
void main() {
  group('Product', () {
    test('discountPercent is null when there is no MRP', () {
      const p = Product(id: '1', name: 'Test', price: 100, stock: 5);
      expect(p.discountPercent, isNull);
    });

    test('discountPercent is null when MRP equals price', () {
      const p = Product(id: '1', name: 'Test', price: 100, mrp: 100, stock: 5);
      expect(p.discountPercent, isNull);
    });

    test('discountPercent rounds correctly', () {
      const p = Product(id: '1', name: 'Test', price: 75, mrp: 100, stock: 5);
      expect(p.discountPercent, 25);
    });

    test('inStock / isLowStock thresholds', () {
      const out = Product(id: '1', name: 'Test', price: 10, stock: 0);
      const low = Product(id: '1', name: 'Test', price: 10, stock: 3);
      const plenty = Product(id: '1', name: 'Test', price: 10, stock: 50);
      expect(out.inStock, isFalse);
      expect(out.isLowStock, isFalse);
      expect(low.inStock, isTrue);
      expect(low.isLowStock, isTrue);
      expect(plenty.inStock, isTrue);
      expect(plenty.isLowStock, isFalse);
    });

    test('coverImageUrl falls back to null with no images', () {
      const p = Product(id: '1', name: 'Test', price: 10, stock: 1);
      expect(p.coverImageUrl, isNull);
    });

    test('coverImageUrl uses the lowest sort_order image', () {
      final p = Product.fromJson({
        'id': '1',
        'name': 'Test',
        'price': 10,
        'stock': 1,
        'product_images': [
          {'id': 'b', 'url': 'https://example.com/b.jpg', 'sort_order': 1},
          {'id': 'a', 'url': 'https://example.com/a.jpg', 'sort_order': 0},
        ],
      });
      expect(p.coverImageUrl, 'https://example.com/a.jpg');
    });
  });

  group('Address', () {
    test('fullText skips blank optional parts', () {
      const a = Address(id: '1', label: 'Home', line1: '12 Main Rd', city: 'Hajipur', state: 'Bihar');
      expect(a.fullText, '12 Main Rd, Hajipur, Bihar');
    });

    test('fullText includes optional parts when present', () {
      const a = Address(
        id: '1',
        label: 'Home',
        line1: '12 Main Rd',
        line2: 'Near Station',
        landmark: 'Opp. Temple',
        city: 'Hajipur',
        state: 'Bihar',
        pincode: '844101',
      );
      expect(a.fullText, '12 Main Rd, Near Station, Opp. Temple, Hajipur, Bihar, 844101');
    });
  });

  group('Order status parsing', () {
    test('orderStatusFromString maps known values', () {
      expect(orderStatusFromString('confirmed'), OrderStatus.confirmed);
      expect(orderStatusFromString('in_transit'), OrderStatus.inTransit);
      expect(orderStatusFromString('fulfilled'), OrderStatus.fulfilled);
      expect(orderStatusFromString('cancelled'), OrderStatus.cancelled);
    });

    test('orderStatusFromString defaults unknown values to newOrder', () {
      expect(orderStatusFromString('something-unexpected'), OrderStatus.newOrder);
    });

    test('paymentStatusFromString defaults unknown values to pending', () {
      expect(paymentStatusFromString('nonsense'), PaymentStatus.pending);
      expect(paymentStatusFromString('paid'), PaymentStatus.paid);
    });
  });
}
