import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import '../../core/env.dart';
import '../../core/theme.dart';
import '../../models/address.dart';
import '../../services/cart_provider.dart';
import '../../services/order_service.dart';
import 'widgets/address_form_sheet.dart';

enum _DeliveryMode { delivery, pickup }
enum _PaymentMethod { cod, online }

class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key});

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  late final Razorpay _razorpay;
  _DeliveryMode _mode = _DeliveryMode.delivery;
  _PaymentMethod _payment = _PaymentMethod.cod;
  String? _selectedAddressId;
  final _couponController = TextEditingController();
  bool _placing = false;
  bool _refreshedCart = false;
  List<String> _cartNotes = const [];

  // Holds the order id we're mid-payment for, so Razorpay's async callbacks
  // (which can't take extra params) know what to verify/finalize.
  String? _pendingOrderId;
  String? _pendingOrderCode;

  @override
  void initState() {
    super.initState();
    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _onPaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _onPaymentError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _onExternalWallet);
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshCart());
  }

  @override
  void dispose() {
    _razorpay.clear();
    _couponController.dispose();
    super.dispose();
  }

  Future<void> _refreshCart() async {
    final notes = await ref.read(cartProvider.notifier).refreshFromServer();
    if (!mounted) return;
    setState(() {
      _refreshedCart = true;
      _cartNotes = notes;
    });
    for (final note in notes) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(note)));
    }
  }

  Future<void> _addAddress() async {
    final address = await showAddAddressSheet(context);
    if (address == null) return;
    try {
      final saved = await ref.read(orderServiceProvider).addAddress(address);
      ref.invalidate(addressesProvider);
      if (!mounted) return;
      setState(() => _selectedAddressId = saved.id);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not save address. Please try again.')));
    }
  }

  Future<void> _placeOrder() async {
    final cartItems = ref.read(cartProvider);
    if (cartItems.isEmpty) return;
    if (_mode == _DeliveryMode.delivery && _selectedAddressId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select or add a delivery address.')));
      return;
    }

    setState(() => _placing = true);
    try {
      final order = await ref.read(orderServiceProvider).createOrder(
            items: cartItems.map((c) => {'product_id': c.product.id, 'qty': c.qty}).toList(),
            deliveryMode: _mode == _DeliveryMode.delivery ? 'delivery' : 'pickup',
            addressId: _mode == _DeliveryMode.delivery ? _selectedAddressId : null,
            couponCode: _couponController.text.trim().isEmpty ? null : _couponController.text.trim(),
            paymentMethod: _payment == _PaymentMethod.online ? 'online' : 'cod',
          );
      await _handleOrderCreated(order.id, order.orderCode, order.grandTotal);
    } on OrderException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not place your order. Please try again.')));
    } finally {
      if (mounted) setState(() => _placing = false);
    }
  }

  Future<void> _handleOrderCreated(String orderId, String orderCode, double grandTotal) async {
    if (_payment == _PaymentMethod.cod) {
      ref.read(cartProvider.notifier).clear();
      if (!mounted) return;
      context.go('/order-success/$orderCode');
      return;
    }

    // Online payment: open Razorpay checkout for the order the server just
    // created. Cart is only cleared after payment succeeds and is verified.
    try {
      final rzpInfo = await ref.read(orderServiceProvider).createRazorpayOrder(orderId);
      _pendingOrderId = orderId;
      _pendingOrderCode = orderCode;
      _razorpay.open({
        'key': rzpInfo.keyId.isNotEmpty ? rzpInfo.keyId : Env.razorpayKeyId,
        'order_id': rzpInfo.rzpOrderId,
        'amount': rzpInfo.amountPaise,
        'currency': rzpInfo.currency,
        'name': 'Rishikesh Enterprises',
        'description': 'Order $orderCode',
        'prefill': {'contact': '', 'email': ''},
        'theme': {'color': '#D21F26'},
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Order $orderCode was created but payment could not start. Find it under My Orders to pay again.'),
      ));
      context.go('/order-success/$orderCode');
    }
  }

  Future<void> _onPaymentSuccess(PaymentSuccessResponse response) async {
    final orderId = _pendingOrderId;
    final orderCode = _pendingOrderCode;
    if (orderId == null || orderCode == null) return;
    try {
      await ref.read(orderServiceProvider).verifyPayment(
            orderId: orderId,
            rzpOrderId: response.orderId ?? '',
            rzpPaymentId: response.paymentId ?? '',
            signature: response.signature ?? '',
          );
      ref.read(cartProvider.notifier).clear();
      if (!mounted) return;
      context.go('/order-success/$orderCode');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Payment received but verification failed. Contact us with order $orderCode — do not pay again.'),
      ));
      context.go('/order-success/$orderCode');
    }
  }

  void _onPaymentError(PaymentFailureResponse response) {
    final orderCode = _pendingOrderCode;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(orderCode == null
          ? 'Payment failed or was cancelled.'
          : 'Payment failed or was cancelled. Order $orderCode is saved — you can pay again from My Orders.'),
    ));
    if (orderCode != null) context.go('/order-success/$orderCode');
  }

  void _onExternalWallet(ExternalWalletResponse response) {
    // No-op: Razorpay handles external wallet UX; we just wait for success/error.
  }

  @override
  Widget build(BuildContext context) {
    final subtotal = ref.watch(cartSubtotalProvider);
    final addressesAsync = ref.watch(addressesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Checkout')),
      body: !_refreshedCart
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _SectionCard(
                  title: 'Delivery mode',
                  child: Row(
                    children: [
                      Expanded(
                        child: RadioListTile<_DeliveryMode>(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          value: _DeliveryMode.delivery,
                          groupValue: _mode,
                          title: const Text('Home delivery'),
                          onChanged: (v) => setState(() => _mode = v!),
                        ),
                      ),
                      Expanded(
                        child: RadioListTile<_DeliveryMode>(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          value: _DeliveryMode.pickup,
                          groupValue: _mode,
                          title: const Text('Store pickup'),
                          onChanged: (v) => setState(() => _mode = v!),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                if (_mode == _DeliveryMode.delivery)
                  _SectionCard(
                    title: 'Delivery address',
                    trailing: TextButton(onPressed: _addAddress, child: const Text('+ Add new')),
                    child: addressesAsync.when(
                      data: (addresses) {
                        if (addresses.isEmpty) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: Text('No saved addresses yet — add one to continue.', style: TextStyle(color: AppColors.muted)),
                          );
                        }
                        _selectedAddressId ??= addresses.firstWhere(
                          (a) => a.isDefault,
                          orElse: () => addresses.first,
                        ).id;
                        return Column(
                          children: addresses.map((a) {
                            return RadioListTile<String>(
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                              value: a.id,
                              groupValue: _selectedAddressId,
                              onChanged: (v) => setState(() => _selectedAddressId = v),
                              title: Text(a.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                              subtitle: Text(a.fullText, style: const TextStyle(fontSize: 12)),
                            );
                          }).toList(),
                        );
                      },
                      loading: () => const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                      ),
                      error: (_, __) => const Text('Could not load addresses.', style: TextStyle(color: AppColors.danger)),
                    ),
                  )
                else
                  const _SectionCard(
                    title: 'Store pickup',
                    child: Text(
                      "Rishikesh Enterprises\nMain Road, Hajipur, Vaishali, Bihar\nWe'll notify you when your order is ready.",
                      style: TextStyle(color: AppColors.muted, height: 1.5),
                    ),
                  ),
                const SizedBox(height: 12),
                _SectionCard(
                  title: 'Coupon code',
                  child: TextField(
                    controller: _couponController,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(hintText: 'Enter coupon code (optional)', isDense: true),
                  ),
                ),
                const SizedBox(height: 12),
                _SectionCard(
                  title: 'Payment method',
                  child: Column(
                    children: [
                      RadioListTile<_PaymentMethod>(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        value: _PaymentMethod.cod,
                        groupValue: _payment,
                        title: const Text('Cash on Delivery'),
                        subtitle: const Text('₹50 COD fee applies', style: TextStyle(fontSize: 12)),
                        onChanged: (v) => setState(() => _payment = v!),
                      ),
                      RadioListTile<_PaymentMethod>(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        value: _PaymentMethod.online,
                        groupValue: _payment,
                        title: const Text('Pay online'),
                        subtitle: const Text('UPI, cards, netbanking via Razorpay', style: TextStyle(fontSize: 12)),
                        onChanged: (v) => setState(() => _payment = v!),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _SectionCard(
                  title: 'Order summary',
                  child: Column(
                    children: [
                      _summaryRow('Subtotal', '₹${subtotal.toStringAsFixed(0)}'),
                      if (_payment == _PaymentMethod.cod) _summaryRow('COD fee', '₹50'),
                      const Divider(),
                      _summaryRow(
                        'Estimated total',
                        '₹${(subtotal + (_payment == _PaymentMethod.cod ? 50 : 0)).toStringAsFixed(0)}',
                        bold: true,
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Final total (with any coupon discount) is confirmed after you place the order.',
                        style: TextStyle(fontSize: 11, color: AppColors.muted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ElevatedButton(
            onPressed: _placing ? null : _placeOrder,
            child: _placing
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                : Text(_payment == _PaymentMethod.cod ? 'Place order (COD)' : 'Proceed to pay'),
          ),
        ),
      ),
    );
  }

  Widget _summaryRow(String label, String value, {bool bold = false}) {
    final style = TextStyle(
      fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
      fontSize: bold ? 15 : 13,
      color: AppColors.ink,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [Text(label, style: style), Text(value, style: style)],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget? trailing;
  const _SectionCard({required this.title, required this.child, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.ink)),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }
}
