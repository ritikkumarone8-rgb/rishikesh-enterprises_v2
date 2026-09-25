import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme.dart';
import '../../../models/review.dart';
import '../../../services/auth_service.dart';
import '../../../services/catalog_service.dart';

/// Customer reviews list + "write a review" entry point for the product
/// detail page. Reviews themselves are already fully modeled server-side
/// (backend/sql/001_schema.sql: `reviews` table, RLS, the rating-average
/// trigger) — this widget is purely the UI on top of that existing data.
class ReviewsSection extends ConsumerWidget {
  final String productId;
  const ReviewsSection({super.key, required this.productId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loggedIn = ref.watch(isLoggedInProvider);
    final reviewsAsync = ref.watch(productReviewsProvider(productId));
    final myReviewAsync = loggedIn ? ref.watch(myReviewProvider(productId)) : const AsyncValue.data(null);
    final canReviewAsync = loggedIn ? ref.watch(canReviewProductProvider(productId)) : const AsyncValue.data(false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Customer reviews', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.ink)),
        const SizedBox(height: 10),
        reviewsAsync.when(
          data: (reviews) {
            if (reviews.isEmpty) {
              return const Text(
                'No reviews yet — be the first to review this product.',
                style: TextStyle(fontSize: 13, color: AppColors.muted),
              );
            }
            return Column(
              children: reviews.map((r) => _ReviewTile(review: r)).toList(),
            );
          },
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)),
          ),
          error: (_, __) => const Text("Couldn't load reviews right now.", style: TextStyle(fontSize: 13, color: AppColors.muted)),
        ),
        const SizedBox(height: 12),
        if (!loggedIn)
          OutlinedButton.icon(
            icon: const Icon(Icons.login, size: 16),
            label: const Text('Log in to write a review'),
            onPressed: () => context.push('/login'),
          )
        else
          myReviewAsync.when(
            data: (mine) {
              if (mine != null) {
                return OutlinedButton.icon(
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('Edit your review'),
                  onPressed: () => _openWriteReviewDialog(context, ref, existing: mine),
                );
              }
              return canReviewAsync.when(
                data: (eligible) => eligible
                    ? OutlinedButton.icon(
                        icon: const Icon(Icons.rate_review_outlined, size: 16),
                        label: const Text('Write a review'),
                        onPressed: () => _openWriteReviewDialog(context, ref, existing: null),
                      )
                    : const Text(
                        'You can write a review once your order for this product is delivered.',
                        style: TextStyle(fontSize: 12, color: AppColors.muted),
                      ),
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
      ],
    );
  }

  void _openWriteReviewDialog(BuildContext context, WidgetRef ref, {required Review? existing}) {
    showDialog(
      context: context,
      builder: (_) => _WriteReviewDialog(productId: productId, existing: existing),
    ).then((submitted) {
      if (submitted == true) {
        ref.invalidate(productReviewsProvider(productId));
        ref.invalidate(myReviewProvider(productId));
        ref.invalidate(canReviewProductProvider(productId));
        ref.invalidate(productDetailProvider(productId)); // avg_rating/rating_count changed
      }
    });
  }
}

class _ReviewTile extends StatelessWidget {
  final Review review;
  const _ReviewTile({required this.review});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(color: AppColors.ok, borderRadius: BorderRadius.circular(5)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${review.rating}', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                    const SizedBox(width: 3),
                    const Icon(Icons.star, color: Colors.white, size: 12),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Text('Verified buyer', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.ink)),
              const Spacer(),
              Text(_timeAgo(review.createdAt), style: const TextStyle(fontSize: 11, color: AppColors.muted)),
            ],
          ),
          if ((review.comment ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(review.comment!.trim(), style: const TextStyle(fontSize: 13, color: AppColors.ink, height: 1.4)),
          ],
        ],
      ),
    );
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inDays >= 365) return '${(diff.inDays / 365).floor()}y ago';
    if (diff.inDays >= 30) return '${(diff.inDays / 30).floor()}mo ago';
    if (diff.inDays >= 1) return '${diff.inDays}d ago';
    if (diff.inHours >= 1) return '${diff.inHours}h ago';
    if (diff.inMinutes >= 1) return '${diff.inMinutes}m ago';
    return 'just now';
  }
}

class _WriteReviewDialog extends ConsumerStatefulWidget {
  final String productId;
  final Review? existing;
  const _WriteReviewDialog({required this.productId, required this.existing});

  @override
  ConsumerState<_WriteReviewDialog> createState() => _WriteReviewDialogState();
}

class _WriteReviewDialogState extends ConsumerState<_WriteReviewDialog> {
  late int _rating = widget.existing?.rating ?? 5;
  late final _commentController = TextEditingController(text: widget.existing?.comment ?? '');
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(catalogServiceProvider).submitReview(
            widget.productId,
            rating: _rating,
            comment: _commentController.text,
          );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Could not save your review. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing != null ? 'Edit your review' : 'Write a review'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (i) {
              final starIndex = i + 1;
              return IconButton(
                icon: Icon(
                  starIndex <= _rating ? Icons.star : Icons.star_border,
                  color: AppColors.accent,
                  size: 28,
                ),
                onPressed: () => setState(() => _rating = starIndex),
              );
            }),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: _commentController,
            maxLines: 3,
            maxLength: 500,
            decoration: const InputDecoration(hintText: 'Share what you liked or didn’t (optional)'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 4),
            Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 12)),
          ],
        ],
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Submit'),
        ),
      ],
    );
  }
}
