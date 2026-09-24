/// Build-time configuration.
///
/// These are injected at BUILD time with `--dart-define`, never hardcoded
/// in source. (The old website hardcoded its Supabase URL/key directly in
/// the HTML — fine for the anon key specifically, since Row Level Security
/// is what actually protects the data either way.) But keeping it out of
/// source control still means different environments (dev/staging/prod
/// Supabase projects) don't require editing code to switch, and nobody
/// accidentally commits a *different*, more sensitive key here later.
///
/// Run locally with, e.g.:
///   flutter run \
///     --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
///     --dart-define=SUPABASE_ANON_KEY=sb_publishable_xxx \
///     --dart-define=RAZORPAY_KEY_ID=rzp_test_xxx \
///     --dart-define=GOOGLE_WEB_CLIENT_ID=xxxx.apps.googleusercontent.com
///
/// CI (see .github/workflows/build.yml) passes these from GitHub Actions
/// secrets so they never appear in the repo at all.
class Env {
  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://YOUR-PROJECT.supabase.co',
  );

  static const supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'YOUR-ANON-PUBLISHABLE-KEY',
  );

  /// Public Razorpay key id — safe to ship client-side by design (it's how
  /// Razorpay Checkout identifies your account). The matching SECRET key
  /// lives only in Supabase Edge Function secrets, never in this app.
  static const razorpayKeyId = String.fromEnvironment(
    'RAZORPAY_KEY_ID',
    defaultValue: 'rzp_test_xxxxxxxxxxxx',
  );

  /// The *Web application* OAuth client ID from Google Cloud Console —
  /// passed to `GoogleSignIn.initialize(serverClientId: ...)` on Android so
  /// Supabase can verify the ID token it gets back. This is a public
  /// identifier (not a secret) — the matching Client Secret never appears
  /// in this app; it lives only in the Supabase dashboard's Google provider
  /// settings. See docs/BACKEND_SETUP.md for exactly where to get this.
  static const googleWebClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
    defaultValue: '',
  );

  static bool get isGoogleSignInConfigured => googleWebClientId.isNotEmpty;

  static bool get isConfigured =>
     !supabaseUrl.contains('YOUR-PROJECT') && !supabaseAnonKey.contains('YOUR-ANON');
}
