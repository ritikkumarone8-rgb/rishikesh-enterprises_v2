import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../models/product.dart';
import '../../models/review.dart';
import '../../services/catalog_service.dart';
import '../../services/cart_provider.dart';
import '../../services/auth_service.dart';
import 'widgets/image_gallery.dart';
import 'widgets/reviews_section.dart';

class ProductDetailScreen extends ConsumerWidget {
  final String productId;
  const ProductDetailScreen({super.key, required this.productId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productAsync = ref.watch(productDetailProvider(productId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Product'),
        actions: [
          IconButton(
            icon: const Icon(Icons.shopping_cart_outlined),
            onPressed: () => context.push('/cart'),
          ),
        ],
      ),
      body: productAsync.when(
        data: (product) {
          if (product == null) {
            return const Center(child: Text('This product is no longer available.', style: TextStyle(color: AppColors.muted)));
          }
          return _ProductDetailBody(product: product);
        },
        loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        error: (_, __) => const Center(
          child: Text('Could not load this product. Please go back and try again.', style: TextStyle(color: AppColors.muted)),
        ),
      ),
    );
  }
}

class _ProductDetailBody extends ConsumerWidget {
  final Product product;
  const _ProductDetailBody({required this.product});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final qty = ref.watch(cartProvider.select((items) {
      final match = items.where((i) => i.product.id == product.id);
      return match.isEmpty ? 0 : match.first.qty;
    }));

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 100),
            children: [
              ProductImageGallery(images: product.images),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (product.brandName != null)
                      Text(product.brandName!.toUpperCase(),
                          style: const TextStyle(fontSize: 12, color: AppColors.brand, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                    const SizedBox(height: 4),
                    Text(product.name,
                        style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.ink, height: 1.3)),
                    const SizedBox(height: 8),
                    if (product.ratingCount > 0)
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(color: AppColors.ok, borderRadius: BorderRadius.circular(5)),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(product.avgRating.toStringAsFixed(1),
                                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                                const SizedBox(width: 3),
                                const Icon(Icons.star, color: Colors.white, size: 12),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text('${product.ratingCount} ratings', style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                        ],
                      ),
                    const SizedBox(height: 14),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('₹${product.price.toStringAsFixed(0)}',
                            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: AppColors.ink)),
                        if (product.mrp != null && product.mrp! > product.price) ...[
                          const SizedBox(width: 10),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text('₹${product.mrp!.toStringAsFixed(0)}',
                                style: const TextStyle(fontSize: 15, color: AppColors.muted, decoration: TextDecoration.lineThrough)),
                          ),
                          const SizedBox(width: 8),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Text('${product.discountPercent}% off',
                                style: const TextStyle(fontSize: 14, color: AppColors.ok, fontWeight: FontWeight.w800)),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 10),
                    _StockPill(product: product),
                    const SizedBox(height: 20),
                    const Divider(),
                    const SizedBox(height: 12),
                    const Text('Product details', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.ink)),
                    const SizedBox(height: 8),
                    Text(
                      (product.description?.trim().isNotEmpty ?? false)
                          ? product.description!
                          : 'No additional details for this product yet.',
                      style: const TextStyle(fontSize: 14, color: AppColors.ink, height: 1.5),
                    ),
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 12),
                    Row(
                      children: const [
                        Icon(Icons.verified_user_outlined, size: 18, color: AppColors.ok),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text('Genuine product, sourced directly from Havells & authorized brands.',
                              style: TextStyle(fontSize: 12, color: AppColors.muted)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: const [
                        Icon(Icons.storefront_outlined, size: 18, color: AppColors.brand),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text('Sold by Rishikesh Enterprises, Hajipur — pickup or local delivery available.',
                              style: TextStyle(fontSize: 12, color: AppColors.muted)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    const Divider(),
                    const SizedBox(height: 12),
                    ReviewsSection(productId: product.id),
                  ],
                ),
              ),
            ],
          ),
        ),
        _BottomBar(product: product, qty: qty),
      ],
    );
  }
}

class _StockPill extends StatelessWidget {
  final Product product;
  const _StockPill({required this.product});

  @override
  Widget build(BuildContext context) {
    if (!product.inStock) {
      return const _Pill(text: 'Out of stock', color: AppColors.danger);
    }
    if (product.isLowStock) {
      return _Pill(text: 'Only ${product.stock} left — order soon', color: AppColors.warn);
    }
    return const _Pill(text: 'In stock', color: AppColors.ok);
  }
}

class _Pill extends StatelessWidget {
  final String text;
  final Color color;
  const _Pill({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
      child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
    );
  }
}

class _BottomBar extends ConsumerWidget {
  final Product product;
  final int qty;
  const _BottomBar({required this.product, required this.qty});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: const BoxDecoration(
          color: AppColors.card,
          border: Border(top: BorderSide(color: AppColors.line)),
        ),
        child: !product.inStock
            ? const SizedBox(
                width: double.infinity,
                child: ElevatedButton(onPressed: null, child: Text('Out of stock')),
              )
            : qty == 0
                ? SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.shopping_cart_outlined, size: 18),
                      label: const Text('Add to cart'),
                      onPressed: () {
                        final err = ref.read(cartProvider.notifier).add(product);
                        ScaffoldMessenger.of(context)
                          ..hideCurrentSnackBar()
                          ..showSnackBar(SnackBar(
                            content: Text(err ?? '${product.name} added to cart'),
                            duration: const Duration(seconds: 2),
                            action: err == null
                                ? SnackBarAction(label: 'VIEW CART', textColor: Colors.white, onPressed: () => context.push('/cart'))
                                : null,
                          ));
                      },
                    ),
                  )
                : Row(
                    children: [
                      Container(
                        decoration: BoxDecoration(color: AppColors.brand, borderRadius: BorderRadius.circular(10)),
                        child: Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.remove, color: Colors.white, size: 18),
                              onPressed: () => ref.read(cartProvider.notifier).decrement(product.id),
                            ),
                            Text('$qty', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
                            IconButton(
                              icon: const Icon(Icons.add, color: Colors.white, size: 18),
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
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => context.push('/cart'),
                          child: const Text('Go to cart'),
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }
}
