import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../models/order.dart';
import '../../services/order_service.dart';

class OrderHistoryScreen extends ConsumerWidget {
  const OrderHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(myOrdersProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('My Orders'), automaticallyImplyLeading: false),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(myOrdersProvider);
          await ref.read(myOrdersProvider.future);
        },
        child: ordersAsync.when(
          data: (orders) {
            if (orders.isEmpty) {
              return ListView(
                children: [
                  SizedBox(
                    height: MediaQuery.of(context).size.height * 0.6,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.receipt_long_outlined, size: 56, color: AppColors.muted),
                          const SizedBox(height: 12),
                          const Text('No orders yet', style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.ink)),
                          const SizedBox(height: 6),
                          const Text('Your past orders will show up here.', style: TextStyle(color: AppColors.muted)),
                          const SizedBox(height: 16),
                          ElevatedButton(onPressed: () => context.go('/home'), child: const Text('Start shopping')),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: orders.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) => _OrderTile(order: orders[i]),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          error: (_, __) => const Center(child: Text('Could not load your orders.', style: TextStyle(color: AppColors.muted))),
        ),
      ),
    );
  }
}

class _OrderTile extends StatelessWidget {
  final Order order;
  const _OrderTile({required this.order});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.push('/order/${order.orderCode}'),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.line),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Order #${order.orderCode}', style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.ink)),
                  const SizedBox(height: 4),
                  Text(DateFormat('d MMM yyyy, h:mm a').format(order.createdAt.toLocal()),
                      style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                  const SizedBox(height: 4),
                  Text('${order.items.length} item${order.items.length == 1 ? '' : 's'} · ₹${order.grandTotal.toStringAsFixed(0)}',
                      style: const TextStyle(fontSize: 13, color: AppColors.ink, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            _StatusChip(status: order.status),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final OrderStatus status;
  const _StatusChip({required this.status});

  (Color, String) get _style => switch (status) {
        OrderStatus.newOrder => (AppColors.warn, 'Placed'),
        OrderStatus.confirmed => (AppColors.brand, 'Confirmed'),
        OrderStatus.inTransit => (AppColors.brand, 'On the way'),
        OrderStatus.fulfilled => (AppColors.ok, 'Delivered'),
        OrderStatus.cancelled => (AppColors.danger, 'Cancelled'),
      };

  @override
  Widget build(BuildContext context) {
    final (color, label) = _style;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 11)),
    );
  }
}
