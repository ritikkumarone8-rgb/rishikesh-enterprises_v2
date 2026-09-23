import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';
import '../../../core/theme.dart';
import '../../../models/product.dart';

/// The multi-image product gallery the user specifically asked for: swipe
/// (scroll) through every photo of a product, with a dot indicator, a
/// thumbnail strip for jumping straight to an image, and tap-to-zoom
/// full-screen viewing — the same interaction pattern as Flipkart's
/// product-image carousel.
class ProductImageGallery extends StatefulWidget {
  final List<ProductImage> images;
  const ProductImageGallery({super.key, required this.images});

  @override
  State<ProductImageGallery> createState() => _ProductImageGalleryState();
}

class _ProductImageGalleryState extends State<ProductImageGallery> {
  final _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _openFullScreen(int startIndex) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _FullScreenGallery(images: widget.images, initialIndex: startIndex),
        fullscreenDialog: true,
      ),
    );
  }

  void _jumpTo(int i) {
    _controller.animateToPage(i, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.images.isEmpty) {
      return AspectRatio(
        aspectRatio: 1,
        child: Container(
          color: AppColors.bg,
          alignment: Alignment.center,
          child: const Icon(Icons.image_outlined, size: 56, color: AppColors.muted),
        ),
      );
    }

    return Column(
      children: [
        AspectRatio(
          aspectRatio: 1,
          child: Stack(
            children: [
              PageView.builder(
                controller: _controller,
                itemCount: widget.images.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (context, i) {
                  return GestureDetector(
                    onTap: () => _openFullScreen(i),
                    child: Hero(
                      tag: 'product-image-${widget.images[i].id}',
                      child: CachedNetworkImage(
                        imageUrl: widget.images[i].url,
                        fit: BoxFit.contain,
                        placeholder: (_, __) => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                        errorWidget: (_, __, ___) => const Icon(Icons.broken_image_outlined, color: AppColors.muted),
                      ),
                    ),
                  );
                },
              ),
              if (widget.images.length > 1)
                Positioned(
                  right: 10,
                  bottom: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
                    child: Text('${_index + 1}/${widget.images.length}',
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                  ),
                ),
            ],
          ),
        ),
        if (widget.images.length > 1) ...[
          const SizedBox(height: 8),
          SmoothPageIndicator(
            controller: _controller,
            count: widget.images.length,
            effect: const WormEffect(dotHeight: 6, dotWidth: 6, activeDotColor: AppColors.brand),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 56,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: widget.images.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final selected = i == _index;
                return GestureDetector(
                  onTap: () => _jumpTo(i),
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: selected ? AppColors.brand : AppColors.line, width: selected ? 2 : 1),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: CachedNetworkImage(imageUrl: widget.images[i].url, fit: BoxFit.cover),
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }
}

class _FullScreenGallery extends StatelessWidget {
  final List<ProductImage> images;
  final int initialIndex;
  const _FullScreenGallery({required this.images, required this.initialIndex});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: PhotoViewGallery.builder(
        itemCount: images.length,
        pageController: PageController(initialPage: initialIndex),
        builder: (context, i) => PhotoViewGalleryPageOptions(
          imageProvider: CachedNetworkImageProvider(images[i].url),
          heroAttributes: PhotoViewHeroAttributes(tag: 'product-image-${images[i].id}'),
          minScale: PhotoViewComputedScale.contained,
          maxScale: PhotoViewComputedScale.covered * 3,
        ),
        loadingBuilder: (context, event) => const Center(child: CircularProgressIndicator()),
        backgroundDecoration: const BoxDecoration(color: Colors.black),
      ),
    );
  }
}
