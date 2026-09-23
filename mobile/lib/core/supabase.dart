import 'package:supabase_flutter/supabase_flutter.dart';
import 'env.dart';

/// Single shared Supabase client for the whole app. Initialize once in
/// main.dart via [initSupabase], then use [supabase] anywhere.
SupabaseClient get supabase => Supabase.instance.client;

Future<void> initSupabase() async {
  await Supabase.initialize(
    url: Env.supabaseUrl,
    anonKey: Env.supabaseAnonKey,
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
    ),
  );
}
