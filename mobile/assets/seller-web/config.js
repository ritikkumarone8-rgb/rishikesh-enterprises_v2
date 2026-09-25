// Seller dashboard configuration — bundled copy used when this dashboard is
// embedded inside the Flutter app's WebView (see
// mobile/lib/features/seller/seller_dashboard_screen.dart).
//
// The Flutter host injects the real values as `window.__SEEDED_APP_CONFIG__`
// via WebViewController.runJavaScript() in onPageStarted — i.e. BEFORE this
// script runs — using the same SUPABASE_URL / SUPABASE_ANON_KEY the app
// itself was built with (Env.supabaseUrl / Env.supabaseAnonKey). That way
// this file never needs to hardcode the project's Supabase credentials, and
// the standalone copy at seller-web/config.js (for hosting this dashboard
// on its own, outside the app) is left untouched.
//
// SUPABASE_ANON_KEY is safe to expose in client-side code — it is the
// public key and every table it can touch is still gated by Row Level
// Security policies (see backend/sql/001_schema.sql).
window.APP_CONFIG = window.__SEEDED_APP_CONFIG__ || {
  SUPABASE_URL: 'https://YOUR-PROJECT-REF.supabase.co',
  SUPABASE_ANON_KEY: 'YOUR-ANON-PUBLIC-KEY',
};
