import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/supabase.dart';

/// Phone-OTP auth. This is the fix for the old website's "type any phone
/// number to see anyone's orders" bug: nothing about a customer's identity
/// is ever taken at face value from client input anymore — Supabase Auth
/// verifies the OTP server-side and issues a signed JWT; every subsequent
/// read/write (addresses, orders, ...) is scoped by Postgres Row Level
/// Security to *that* JWT's `auth.uid()`, not to a phone number someone
/// typed into a box.
class AuthService {
  /// Sends a 6-digit OTP by SMS to [e164Phone] (must be in +91XXXXXXXXXX
  /// form). Throws on failure (bad number, SMS provider not configured,
  /// rate limited, etc.) — callers should catch and show a friendly error.
  Future<void> sendOtp(String e164Phone) {
    return supabase.auth.signInWithOtp(phone: e164Phone);
  }

  /// Verifies the OTP the user typed in. On success, Supabase sets up the
  /// session automatically (and our `handle_new_auth_user` DB trigger
  /// creates the matching `customers` row server-side on first login).
  Future<void> verifyOtp(String e164Phone, String otp) async {
    await supabase.auth.verifyOTP(
      phone: e164Phone,
      token: otp,
      type: OtpType.sms,
    );
  }

  Future<void> signOut() => supabase.auth.signOut();

  bool get isLoggedIn => supabase.auth.currentSession != null;
  String? get customerId => supabase.auth.currentUser?.id;
  String? get phone => supabase.auth.currentUser?.phone;
}

final authServiceProvider = Provider<AuthService>((ref) => AuthService());

/// Emits whenever the auth session changes (login, logout, token refresh).
/// Screens/widgets watch this instead of checking `supabase.auth` directly
/// so the UI reacts immediately to login/logout.
final authStateProvider = StreamProvider<AuthState>((ref) {
  return supabase.auth.onAuthStateChange;
});

final isLoggedInProvider = Provider<bool>((ref) {
  final authState = ref.watch(authStateProvider).valueOrNull;
  return (authState?.session ?? supabase.auth.currentSession) != null;
});

final currentCustomerIdProvider = Provider<String?>((ref) {
  ref.watch(authStateProvider); // rebuild on auth changes
  return supabase.auth.currentUser?.id;
});
