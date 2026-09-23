import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme.dart';
import '../../models/product.dart';
import '../../services/catalog_service.dart';
import '../../widgets/product_card.dart';

enum _SortOrder { relevance, priceLowHigh, priceHighLow, ratingHighLow }

final _sortProvider = StateProvider.autoDispose<_SortOrder>((ref) => _SortOrder.relevance);

class CategoryProductsScreen extends ConsumerWidget {
  final String categoryId;
  final String categoryName;
  const CategoryProductsScreen({super.key, required this.categoryId, required this.categoryName});

  List<Product> _sorted(List<Product> products, _SortOrder order) {
    final list = [...products];
    switch (order) {
      case _SortOrder.priceLowHigh:
        list.sort((a, b) => a.price.compareTo(b.price));
        break;
      case _SortOrder.priceHighLow:
        list.sort((a, b) => b.price.compareTo(a.price));
        break;
      case _SortOrder.ratingHighLow:
        list.sort((a, b) => b.avgRating.compareTo(a.avgRating));
        break;
      case _SortOrder.relevance:
        break;
    }
    return list;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsAsync = ref.watch(categoryProductsProvider(categoryId));
    final order = ref.watch(_sortProvider);

    return Scaffold(
      appBar: AppBar(title: Text(categoryName)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: Row(
              children: [
                const Text('Sort by', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
                const SizedBox(width: 10),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _sortChip(ref, order, _SortOrder.relevance, 'Relevance'),
                        _sortChip(ref, order, _SortOrder.priceLowHigh, 'Price: Low to High'),
                        _sortChip(ref, order, _SortOrder.priceHighLow, 'Price: High to Low'),
                        _sortChip(ref, order, _SortOrder.ratingHighLow, 'Rating'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: productsAsync.when(
              data: (products) {
                if (products.isEmpty) {
                  return const Center(
                    child: Text('No products in this category yet.', style: TextStyle(color: AppColors.muted)),
                  );
                }
                final sorted = _sorted(products, order);
                return GridView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: sorted.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.62,
                  ),
                  itemBuilder: (context, i) => ProductCard(product: sorted[i]),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
              error: (_, __) => const Center(
                child: Text('Could not load products. Pull to refresh isn\'t available here — go back and retry.',
                    textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sortChip(WidgetRef ref, _SortOrder current, _SortOrder value, String label) {
    final selected = current == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => ref.read(_sortProvider.notifier).state = value,
        selectedColor: AppColors.brand,
        labelStyle: TextStyle(
          color: selected ? Colors.white : AppColors.ink,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
        backgroundColor: AppColors.card,
        side: BorderSide(color: selected ? AppColors.brand : AppColors.line),
      ),
    );
  }
}
