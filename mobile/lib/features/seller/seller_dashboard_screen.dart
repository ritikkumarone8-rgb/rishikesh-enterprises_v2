import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../core/env.dart';
import '../../core/theme.dart';

/// Hosts the existing `seller-web/` dashboard (plain HTML/CSS/JS, already
/// built and tested standalone) inside the Flutter app, instead of
/// rebuilding seller product/inventory/order management natively. The
/// dashboard is bundled as a Flutter asset (see mobile/assets/seller-web/,
/// pubspec.yaml) and loaded into a WebView.
///
/// The dashboard's own `config.js` reads `window.__SEEDED_APP_CONFIG__` if
/// present (falling back to a placeholder otherwise, for the standalone
/// hosting case). We inject the real Supabase URL/anon key as that global
/// via `runJavaScript` in `onPageStarted` — i.e. before any of the page's
/// own scripts (config.js, then app.js) run — reusing the exact same
/// values this app was built with (`Env.supabaseUrl` / `Env.supabaseAnonKey`)
/// rather than hardcoding or re-reading them from anywhere else.
///
/// Once loaded, the dashboard handles its own seller login (email/password,
/// verified server-side via Supabase Auth + the `is_seller()` RLS check) —
/// this screen is just the shell that hosts it.
class SellerDashboardScreen extends StatefulWidget {
  const SellerDashboardScreen({super.key});

  @override
  State<SellerDashboardScreen> createState() => _SellerDashboardScreenState();
}

class _SellerDashboardScreenState extends State<SellerDashboardScreen> {
  late final WebViewController _controller;
  bool _loading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(AppColors.bg)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) => _injectConfig(),
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
          onWebResourceError: (error) {
            if (mounted) {
              setState(() {
                _loading = false;
                _loadError = 'Could not load the seller dashboard (${error.description}).';
              });
            }
          },
        ),
      )
      ..loadFlutterAsset('assets/seller-web/index.html');
  }

  Future<void> _injectConfig() async {
    final url = _jsString(Env.supabaseUrl);
    final anonKey = _jsString(Env.supabaseAnonKey);
    await _controller.runJavaScript(
      'window.__SEEDED_APP_CONFIG__ = { SUPABASE_URL: $url, SUPABASE_ANON_KEY: $anonKey };',
    );
  }

  /// Encodes a Dart string as a safe, single-quoted JS string literal.
  String _jsString(String value) {
    final escaped = value.replaceAll(r'\', r'\\').replaceAll("'", r"\'");
    return "'$escaped'";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Seller dashboard')),
      body: !Env.isConfigured
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'This build was not configured with a Supabase project, so the '
                  'seller dashboard has nothing to connect to.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.muted),
                ),
              ),
            )
          : Stack(
              children: [
                WebViewWidget(controller: _controller),
                if (_loading)
                  const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                if (_loadError != null)
                  Container(
                    color: AppColors.bg,
                    alignment: Alignment.center,
                    padding: const EdgeInsets.all(24),
                    child: Text(_loadError!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.danger)),
                  ),
              ],
            ),
    );
  }
}
