import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/supabase.dart';
import '../features/splash/splash_screen.dart';
import '../features/auth/phone_entry_screen.dart';
import '../features/auth/otp_screen.dart';
import '../features/home/home_screen.dart';
import '../features/search/search_screen.dart';
import '../features/category/category_products_screen.dart';
import '../features/product/product_detail_screen.dart';
import '../features/cart/cart_screen.dart';
import '../features/checkout/checkout_screen.dart';
import '../features/checkout/order_success_screen.dart';
import '../features/orders/order_history_screen.dart';
import '../features/orders/order_detail_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/profile/addresses_screen.dart';
import '../widgets/main_shell.dart';

/// Refreshes the router whenever auth state changes, so a login/logout
/// immediately re-runs `redirect` below instead of leaving a stale screen
/// (e.g. showing Checkout to someone who just logged out mid-flow).
class _AuthRefreshNotifier extends ChangeNotifier {
  _AuthRefreshNotifier() {
    supabase.auth.onAuthStateChange.listen((_) => notifyListeners());
  }
}

final _authRefreshNotifierProvider = Provider<_AuthRefreshNotifier>((ref) {
  final notifier = _AuthRefreshNotifier();
  ref.onDispose(notifier.dispose);
  return notifier;
});

final routerProvider = Provider<GoRouter>((ref) {
  final authRefresh = ref.watch(_authRefreshNotifierProvider);

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: authRefresh,
    redirect: (context, state) {
      final loggedIn = supabase.auth.currentSession != null;
      final loc = state.matchedLocation;
      final isAuthRoute = loc == '/login' || loc == '/otp';
      final isSplash = loc == '/splash';
      final needsAuth = loc == '/checkout' || loc == '/orders' || loc == '/profile/addresses';

      if (isSplash) return null; // splash decides where to go next itself
      if (needsAuth && !loggedIn) return '/login';
      if (isAuthRoute && loggedIn) return '/home';
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/login', builder: (_, __) => const PhoneEntryScreen()),
      GoRoute(
        path: '/otp',
        builder: (_, state) => OtpScreen(phone: state.extra as String? ?? ''),
      ),

      ShellRoute(
        builder: (context, state, child) => MainShell(child: child),
        routes: [
          GoRoute(path: '/home', builder: (_, __) => const HomeScreen()),
          GoRoute(path: '/search', builder: (_, __) => const SearchScreen()),
          GoRoute(path: '/cart', builder: (_, __) => const CartScreen()),
          GoRoute(path: '/orders', builder: (_, __) => const OrderHistoryScreen()),
          GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen()),
        ],
      ),

      GoRoute(
        path: '/category/:id',
        builder: (_, state) => CategoryProductsScreen(
          categoryId: state.pathParameters['id']!,
          categoryName: state.extra as String? ?? 'Products',
        ),
      ),
      GoRoute(
        path: '/product/:id',
        builder: (_, state) => ProductDetailScreen(productId: state.pathParameters['id']!),
      ),
      GoRoute(path: '/checkout', builder: (_, __) => const CheckoutScreen()),
      GoRoute(
        path: '/order-success/:code',
        builder: (_, state) => OrderSuccessScreen(orderCode: state.pathParameters['code']!),
      ),
      GoRoute(
        path: '/order/:code',
        builder: (_, state) => OrderDetailScreen(orderCode: state.pathParameters['code']!),
      ),
      GoRoute(path: '/profile/addresses', builder: (_, __) => const AddressesScreen()),
    ],
  );
});
