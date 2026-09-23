import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';
import '../../../core/theme.dart';
import '../../../services/catalog_service.dart';

/// Auto-scrolling banner carousel for active deals — the "Flipkart big
/// banners at the top" pattern. Tapping a banner jumps straight to its
/// category if it has one.
class DealCarousel extends StatefulWidget {
  final List<Deal> deals;
  const DealCarousel({super.key, required this.deals});

  @override
  State<DealCarousel> createState() => _DealCarouselState();
}

class _DealCarouselState extends State<DealCarousel> {
  final _controller = PageController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.deals.isEmpty) return const SizedBox.shrink();
    return Column(
      children: [
        AspectRatio(
          aspectRatio: 16 / 7,
          child: PageView.builder(
            controller: _controller,
            itemCount: widget.deals.length,
            itemBuilder: (context, i) {
              final deal = widget.deals[i];
              return GestureDetector(
                onTap: () {
                  if (deal.categoryId != null) {
                    context.push('/category/${deal.categoryId}', extra: deal.title);
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: deal.img != null
                        ? CachedNetworkImage(imageUrl: deal.img!, fit: BoxFit.cover, width: double.infinity)
                        : Container(
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                colors: [AppColors.brand, AppColors.brandDark],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                            ),
                            padding: const EdgeInsets.all(16),
                            alignment: Alignment.centerLeft,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(deal.title,
                                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
                                if (deal.description != null) ...[
                                  const SizedBox(height: 4),
                                  Text(deal.description!,
                                      style: const TextStyle(color: Colors.white70, fontSize: 12)),
                                ],
                              ],
                            ),
                          ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        if (widget.deals.length > 1)
          SmoothPageIndicator(
            controller: _controller,
            count: widget.deals.length,
            effect: const WormEffect(dotHeight: 6, dotWidth: 6, activeDotColor: AppColors.brand),
          ),
      ],
    );
  }
}
