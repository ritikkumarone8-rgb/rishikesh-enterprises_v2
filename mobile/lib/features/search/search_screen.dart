import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme.dart';
import '../../services/catalog_service.dart';
import '../../widgets/product_card.dart';

/// Debounced, typo-tolerant product search. The actual "smart" matching
/// (full-text ranking + trigram fuzzy fallback for typos like "buld" ->
/// "Bulb") happens server-side in the `search_products` Postgres RPC — this
/// screen's job is just to feel instant: debounce keystrokes, keep recent
/// searches for one-tap re-search, and show clear empty/error states.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  Timer? _debounce;
  String _query = '';
  final List<String> _recent = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusNode.requestFocus());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      setState(() => _query = value.trim());
    });
  }

  void _runSearch(String value) {
    _debounce?.cancel();
    final trimmed = value.trim();
    setState(() {
      _query = trimmed;
      if (trimmed.isNotEmpty) {
        _recent.remove(trimmed);
        _recent.insert(0, trimmed);
        if (_recent.length > 8) _recent.removeLast();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.only(right: 12),
          child: TextField(
            controller: _controller,
            focusNode: _focusNode,
            textInputAction: TextInputAction.search,
            onChanged: _onChanged,
            onSubmitted: _runSearch,
            decoration: InputDecoration(
              hintText: 'Search products, brands…',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _controller.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () {
                        _controller.clear();
                        setState(() => _query = '');
                      },
                    ),
              contentPadding: const EdgeInsets.symmetric(vertical: 4, horizontal: 14),
            ),
          ),
        ),
      ),
      body: _query.isEmpty ? _RecentSearches(recent: _recent, onTap: (q) {
        _controller.text = q;
        _runSearch(q);
      }) : _SearchResults(query: _query),
    );
  }
}

class _RecentSearches extends StatelessWidget {
  final List<String> recent;
  final ValueChanged<String> onTap;
  const _RecentSearches({required this.recent, required this.onTap});

  @override
  Widget build(BuildContext context) {
    if (recent.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Search our full catalogue — try "LED bulb", "MCB", "ceiling fan" or a brand name.\n'
            "Don't worry about typos, we'll still find it.",
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted),
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Recent searches', style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.ink)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: recent
              .map((q) => ActionChip(
                    label: Text(q),
                    onPressed: () => onTap(q),
                    backgroundColor: AppColors.card,
                    side: const BorderSide(color: AppColors.line),
                  ))
              .toList(),
        ),
      ],
    );
  }
}

class _SearchResults extends ConsumerWidget {
  final String query;
  const _SearchResults({required this.query});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final results = ref.watch(searchResultsProvider(query));
    return results.when(
      data: (products) {
        if (products.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.search_off, size: 40, color: AppColors.muted),
                  const SizedBox(height: 12),
                  Text('No results for "$query"',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
                  const SizedBox(height: 6),
                  const Text('Try a different spelling or a shorter term.',
                      textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted)),
                ],
              ),
            ),
          );
        }
        return GridView.builder(
          padding: const EdgeInsets.all(16),
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
      loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      error: (_, __) => const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text('Something went wrong searching. Please try again.', style: TextStyle(color: AppColors.muted)),
        ),
      ),
    );
  }
}
