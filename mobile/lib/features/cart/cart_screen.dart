import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../models/cart_item.dart';
import '../../services/cart_provider.dart';

class CartScreen extends ConsumerWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(cartProvider);
    final subtotal = ref.watch(cartSubtotalProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text('My Cart${items.isEmpty ? '' : ' (${items.length})'}'),
        actions: [
          if (items.isNotEmpty)
            TextButton(
              onPressed: () => ref.read(cartProvider.notifier).clear(),
              child: const Text('Clear'),
            ),
        ],
      ),
      body: items.isEmpty
          ? _EmptyCart(onShop: () => context.go('/home'))
          : Column(
              children: [
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, i) => _CartTile(item: items[i]),
                  ),
                ),
                _CartSummary(subtotal: subtotal, itemCount: items.length),
              ],
            ),
    );
  }
}

class _EmptyCart extends StatelessWidget {
  final VoidCallback onShop;
  const _EmptyCart({required this.onShop});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.shopping_cart_outlined, size: 64, color: AppColors.muted),
          const SizedBox(height: 12),
          const Text('Your cart is empty', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.ink)),
          const SizedBox(height: 6),
          const Text('Add products to get started', style: TextStyle(color: AppColors.muted)),
          const SizedBox(height: 20),
          ElevatedButton(onPressed: onShop, child: const Text('Start shopping')),
        ],
      ),
    );
  }
}

class _CartTile extends ConsumerWidget {
  final CartItem item;
  const _CartTile({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final product = item.product;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 64,
              height: 64,
              child: product.coverImageUrl != null
                  ? CachedNetworkImage(imageUrl: product.coverImageUrl!, fit: BoxFit.cover)
                  : Container(color: AppColors.bg, child: const Icon(Icons.image_outlined, color: AppColors.muted)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(product.name, maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.ink)),
                const SizedBox(height: 4),
                Text('₹${product.price.toStringAsFixed(0)}',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.ink)),
                if (item.qty > product.stock)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('Only ${product.stock} left in stock',
                        style: const TextStyle(color: AppColors.danger, fontSize: 11, fontWeight: FontWeight.w600)),
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Container(
                      decoration: BoxDecoration(border: Border.all(color: AppColors.line), borderRadius: BorderRadius.circular(8)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.remove, size: 16),
                            onPressed: () => ref.read(cartProvider.notifier).decrement(product.id),
                          ),
                          Text('${item.qty}', style: const TextStyle(fontWeight: FontWeight.w700)),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.add, size: 16),
                            onPressed: () {
                              final err = ref.read(cartProvider.notifier).increment(product.id);
                              if (err != null) {
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: AppColors.muted),
                      onPressed: () => ref.read(cartProvider.notifier).remove(product.id),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CartSummary extends StatelessWidget {
  final double subtotal;
  final int itemCount;
  const _CartSummary({required this.subtotal, required this.itemCount});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: const BoxDecoration(
          color: AppColors.card,
          border: Border(top: BorderSide(color: AppColors.line)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('₹${subtotal.toStringAsFixed(0)}',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.ink)),
                  const Text('Taxes & delivery calculated at checkout', style: TextStyle(fontSize: 11, color: AppColors.muted)),
                ],
              ),
            ),
            SizedBox(
              width: 160,
              child: ElevatedButton(
                onPressed: () => context.push('/checkout'),
                child: const Text('Proceed'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
