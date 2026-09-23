// Seller dashboard configuration.
//
// SUPABASE_ANON_KEY is safe to expose in client-side code — it is the
// public key and every table it can touch is still gated by Row Level
// Security policies (see backend/sql/001_schema.sql). NEVER put the
// service-role key in this file or anywhere in seller-web/ — that key
// bypasses RLS entirely and must only ever live server-side (Edge
// Function secrets), never in a browser-shipped file.
//
// Fill these in after you create the new Supabase project — see
// docs/BACKEND_SETUP.md for the exact steps.
window.APP_CONFIG = {
  SUPABASE_URL: 'https://YOUR-PROJECT-REF.supabase.co',
  SUPABASE_ANON_KEY: 'YOUR-ANON-PUBLIC-KEY',
};
