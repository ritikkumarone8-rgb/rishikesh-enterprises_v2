import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../services/catalog_service.dart';
import '../../widgets/product_card.dart';
import 'widgets/deal_carousel.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(categoriesProvider);
    ref.invalidate(dealsProvider);
    ref.invalidate(popularProductsProvider);
    await Future.wait([
      ref.read(categoriesProvider.future),
      ref.read(dealsProvider.future),
      ref.read(popularProductsProvider.future),
    ]);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(categoriesProvider);
    final deals = ref.watch(dealsProvider);
    final popular = ref.watch(popularProductsProvider);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: 16,
        title: Row(
          children: [
            const Icon(Icons.bolt_rounded, color: AppColors.brand, size: 26),
            const SizedBox(width: 6),
            const Expanded(
              child: Text('Rishikesh Enterprises',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.ink)),
            ),
          ],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () => _refresh(ref),
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: GestureDetector(
                onTap: () => context.push('/search'),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.line),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.search, color: AppColors.muted, size: 20),
                      SizedBox(width: 10),
                      Text('Search for switches, wires, fans, lights…',
                          style: TextStyle(color: AppColors.muted, fontSize: 14)),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            deals.when(
              data: (d) => DealCarousel(deals: d),
              loading: () => const SizedBox(height: 140),
              error: (_, __) => const SizedBox.shrink(),
            ),
            const SizedBox(height: 16),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text('Shop by category',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.ink)),
            ),
            const SizedBox(height: 10),
            categories.when(
              data: (cats) => SizedBox(
                height: 104,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: cats.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 14),
                  itemBuilder: (context, i) {
                    final c = cats[i];
                    return GestureDetector(
                      onTap: () => context.push('/category/${c.id}', extra: c.name),
                      child: SizedBox(
                        width: 72,
                        child: Column(
                          children: [
                            Container(
                              height: 64,
                              width: 64,
                              decoration: BoxDecoration(
                                color: AppColors.card,
                                shape: BoxShape.circle,
                                border: Border.all(color: AppColors.line),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: c.imageUrl != null
                                  ? CachedNetworkImage(imageUrl: c.imageUrl!, fit: BoxFit.cover)
                                  : const Icon(Icons.category_outlined, color: AppColors.brand),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              c.name,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.ink),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              loading: () => const SizedBox(
                height: 104,
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              ),
              error: (_, __) => const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text('Could not load categories', style: TextStyle(color: AppColors.muted)),
              ),
            ),
            const SizedBox(height: 20),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text('Popular products',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.ink)),
            ),
            const SizedBox(height: 10),
            popular.when(
              data: (products) {
                if (products.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Text('No products yet — check back soon.', style: TextStyle(color: AppColors.muted)),
                  );
                }
                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: products.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.62,
                  ),
                  itemBuilder: (context, i) => ProductCard(product: products[i]),
                );
              },
              loading: () => const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              ),
              error: (_, __) => const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text('Could not load products. Pull down to retry.', style: TextStyle(color: AppColors.muted)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
