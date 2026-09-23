import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../models/order.dart';
import '../../services/order_service.dart';

class OrderDetailScreen extends ConsumerWidget {
  final String orderCode;
  const OrderDetailScreen({super.key, required this.orderCode});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orderAsync = ref.watch(orderByCodeProvider(orderCode));

    return Scaffold(
      appBar: AppBar(title: Text('Order #$orderCode')),
      body: orderAsync.when(
        data: (order) {
          if (order == null) {
            return const Center(child: Text('Order not found.', style: TextStyle(color: AppColors.muted)));
          }
          return _OrderDetailBody(order: order);
        },
        loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        error: (_, __) => const Center(child: Text('Could not load this order.', style: TextStyle(color: AppColors.muted))),
      ),
    );
  }
}

class _OrderDetailBody extends StatelessWidget {
  final Order order;
  const _OrderDetailBody({required this.order});

  static const _steps = [
    (OrderStatus.newOrder, 'Order placed', Icons.receipt_long_outlined),
    (OrderStatus.confirmed, 'Confirmed', Icons.check_circle_outline),
    (OrderStatus.inTransit, 'Out for delivery', Icons.local_shipping_outlined),
    (OrderStatus.fulfilled, 'Delivered', Icons.home_outlined),
  ];

  int get _currentStepIndex {
    if (order.status == OrderStatus.cancelled) return -1;
    final i = _steps.indexWhere((s) => s.$1 == order.status);
    return i == -1 ? 0 : i;
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.line),
          ),
          child: order.status == OrderStatus.cancelled
              ? const Row(
                  children: [
                    Icon(Icons.cancel_outlined, color: AppColors.danger),
                    SizedBox(width: 10),
                    Text('This order was cancelled', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.danger)),
                  ],
                )
              : Column(
                  children: List.generate(_steps.length, (i) {
                    final step = _steps[i];
                    final done = i <= _currentStepIndex;
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Column(
                          children: [
                            Icon(step.$3, size: 22, color: done ? AppColors.ok : AppColors.line),
                            if (i != _steps.length - 1)
                              Container(width: 2, height: 28, color: i < _currentStepIndex ? AppColors.ok : AppColors.line),
                          ],
                        ),
                        const SizedBox(width: 12),
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(step.$2,
                              style: TextStyle(
                                fontWeight: done ? FontWeight.w800 : FontWeight.w500,
                                color: done ? AppColors.ink : AppColors.muted,
                              )),
                        ),
                      ],
                    );
                  }),
                ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Placed on ${DateFormat('d MMM yyyy, h:mm a').format(order.createdAt.toLocal())}',
                  style: const TextStyle(fontSize: 12, color: AppColors.muted)),
              const SizedBox(height: 4),
              Text(order.deliveryMode == 'pickup' ? 'Store pickup' : 'Home delivery',
                  style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
              if (order.addressSnapshot != null) ...[
                const SizedBox(height: 4),
                Text(_formatAddress(order.addressSnapshot!), style: const TextStyle(fontSize: 12, color: AppColors.muted)),
              ],
              const SizedBox(height: 4),
              Text(
                order.paymentMethod == 'cod'
                    ? 'Cash on delivery · ${_paymentLabel(order.paymentStatus)}'
                    : 'Paid online · ${_paymentLabel(order.paymentStatus)}',
                style: const TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Items', style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.ink)),
              const SizedBox(height: 8),
              ...order.items.map((item) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text('${item.productName} × ${item.qty}',
                              style: const TextStyle(fontSize: 13, color: AppColors.ink)),
                        ),
                        Text('₹${item.finalAmount.toStringAsFixed(0)}',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.ink)),
                      ],
                    ),
                  )),
              const Divider(),
              _row('Subtotal', '₹${order.subtotal.toStringAsFixed(0)}'),
              if (order.discountTotal > 0) _row('Discount', '-₹${order.discountTotal.toStringAsFixed(0)}', color: AppColors.ok),
              if (order.codFee > 0) _row('COD fee', '₹${order.codFee.toStringAsFixed(0)}'),
              const Divider(),
              _row('Total', '₹${order.grandTotal.toStringAsFixed(0)}', bold: true),
            ],
          ),
        ),
      ],
    );
  }

  String _formatAddress(Map<String, dynamic> a) {
    final parts = [a['line1'], a['line2'], a['landmark'], a['city'], a['state'], a['pincode']]
        .where((e) => e != null && e.toString().trim().isNotEmpty)
        .join(', ');
    return parts;
  }

  String _paymentLabel(PaymentStatus s) => switch (s) {
        PaymentStatus.paid => 'Paid',
        PaymentStatus.failed => 'Payment failed',
        PaymentStatus.cancelled => 'Payment cancelled',
        PaymentStatus.pending => 'Payment pending',
      };

  Widget _row(String label, String value, {bool bold = false, Color? color}) {
    final style = TextStyle(
      fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
      fontSize: bold ? 15 : 13,
      color: color ?? AppColors.ink,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(label, style: style), Text(value, style: style)]),
    );
  }
}
