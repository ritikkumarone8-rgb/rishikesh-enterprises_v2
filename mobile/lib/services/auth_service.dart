import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/env.dart';
import '../core/supabase.dart';

/// Thrown by [AuthService.signInWithGoogle] when the person dismisses the
/// Google account picker instead of picking an account. Callers should
/// treat this as "no-op", not an error — no snackbar needed.
class GoogleSignInCancelled implements Exception {}

/// Phone-OTP + Google sign-in. This is the fix for the old website's "type
/// any phone number to see anyone's orders" bug: nothing about a customer's
/// identity is ever taken at face value from client input anymore —
/// Supabase Auth verifies the OTP (or the Google ID token) server-side and
/// issues a signed JWT; every subsequent read/write (addresses, orders,
/// ...) is scoped by Postgres Row Level Security to *that* JWT's
/// `auth.uid()`, never to anything the client merely claims.
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

  GoogleSignIn? _googleSignIn;

  /// `GoogleSignIn.initialize(...)` must run exactly once before any other
  /// call on the instance. We don't have (and don't need) a Firebase
  /// `google-services.json` in this app, so the *web* OAuth client ID has
  /// to be passed explicitly as `serverClientId` — that's what lets
  /// Supabase verify the ID token this returns. See docs/BACKEND_SETUP.md
  /// for exactly where that client ID comes from.
  Future<GoogleSignIn> _googleSignInInstance() async {
    final existing = _googleSignIn;
    if (existing != null) return existing;

    if (!Env.isGoogleSignInConfigured) {
      // This is the #1 reason "Continue with Google" silently does nothing:
      // the APK was built without --dart-define=GOOGLE_WEB_CLIENT_ID=... (a
      // missing GitHub Actions secret, or a local `flutter run` without the
      // flag). Spelled out in full so it's impossible to mistake for "try
      // again and it might work" — retrying will not help until that
      // build-time value is set. See docs/BACKEND_SETUP.md step 4.
      throw const AuthException(
        'Google sign-in isn\'t set up on this build yet: no GOOGLE_WEB_CLIENT_ID '
        'was baked in at build time. This needs a Google Cloud OAuth client, '
        'the Supabase Google provider configured, and the GOOGLE_WEB_CLIENT_ID '
        'GitHub Actions secret set — see docs/BACKEND_SETUP.md step 4, then '
        'rebuild the app.',
      );
    }

    final instance = GoogleSignIn.instance;
    try {
      await instance.initialize(serverClientId: Env.googleWebClientId).timeout(
            const Duration(seconds: 20),
            onTimeout: () => throw const AuthException(
              'Could not reach Google (initialize timed out). Check your internet '
              'connection and try again.',
            ),
          );
    } on GoogleSignInException catch (e) {
      throw AuthException(
        'Google sign-in could not initialize (${e.code}${e.description != null ? ': ${e.description}' : ''}). '
        'This usually means the Google Cloud OAuth client setup is incomplete '
        'or the GOOGLE_WEB_CLIENT_ID value is wrong — see docs/BACKEND_SETUP.md step 4.',
      );
    }
    _googleSignIn = instance;
    return instance;
  }

  /// Signs in with a native Google account picker, then exchanges the
  /// Google ID token for a Supabase session — no password, nothing stored
  /// by this app. A successful call here fires the same
  /// `supabase.auth.onAuthStateChange` event phone-OTP login does, so the
  /// router's existing redirect logic takes it from there automatically.
  ///
  /// Throws [GoogleSignInCancelled] if the person backs out of the account
  /// picker; throws [AuthException]/other exceptions on real failures
  /// (network, misconfiguration, Supabase rejecting the token) — callers
  /// should catch and show a friendly error, same as [sendOtp]/[verifyOtp].
  Future<void> signInWithGoogle() async {
    final googleSignIn = await _googleSignInInstance();

    if (!googleSignIn.supportsAuthenticate()) {
      // Only expected on platforms this app doesn't ship for (web uses a
      // rendered button instead of authenticate()) — see google_sign_in's
      // docs. Kept as a friendly guard rather than an assumption.
      throw const AuthException('Google sign-in is not supported on this platform.');
    }

    final GoogleSignInAccount googleUser;
    try {
      googleUser = await googleSignIn.authenticate().timeout(
            const Duration(seconds: 45),
            onTimeout: () => throw const AuthException(
              'Google sign-in timed out waiting for the account picker. Make sure '
              'Google Play services is installed and up to date on this device, '
              'then try again.',
            ),
          );
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        throw GoogleSignInCancelled();
      }
      // Surface the real code/description instead of a generic message —
      // e.g. "no credentials available" almost always means the Android
      // OAuth client's package name + SHA-1 in Google Cloud Console doesn't
      // match the key this APK is actually signed with. Getting the exact
      // reason on screen means it doesn't have to be guessed at blind.
      throw AuthException(
        'Google sign-in failed to start (${e.code}${e.description != null ? ': ${e.description}' : ''}). '
        "This is usually the Android OAuth client's package name/SHA-1 not "
        'matching this build\'s signing key, or Google Play services being '
        'missing/outdated on this device — see docs/BACKEND_SETUP.md step 4.1.',
      );
    }

    final idToken = googleUser.authentication.idToken;
    if (idToken == null) {
      throw const AuthException('Google did not return an ID token. Please try again.');
    }

    // Supabase's Google provider needs the access token alongside the ID
    // token. `authorizationForScopes` returns the already-granted
    // authorization silently if there is one; otherwise `authorizeScopes`
    // prompts for the (minimal) email/profile scopes.
    const scopes = ['email', 'profile'];
    final GoogleSignInClientAuthorization authorization;
    try {
      authorization = await googleUser.authorizationClient.authorizationForScopes(scopes) ??
          await googleUser.authorizationClient.authorizeScopes(scopes);
    } on GoogleSignInException catch (e) {
      throw AuthException(
        'Google sign-in could not get authorization (${e.code}${e.description != null ? ': ${e.description}' : ''}).',
      );
    }

    try {
      await supabase.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: authorization.accessToken,
      );
    } on AuthException catch (e) {
      // Supabase itself rejected the token — almost always means the
      // Supabase dashboard's Google provider isn't configured yet (Client
      // ID/Secret, or the "Authorized Client IDs" list missing this app's
      // Android client). Passed through with that context rather than
      // Supabase's raw (often cryptic) message alone.
      throw AuthException(
        'Supabase rejected the Google sign-in (${e.message}). Check '
        'Authentication → Providers → Google in the Supabase dashboard — '
        'Client ID/Secret and Authorized Client IDs — see '
        'docs/BACKEND_SETUP.md step 4.2.',
      );
    }
  }

  Future<void> signOut() async {
    await supabase.auth.signOut();
    // Clears Google's cached account so the picker doesn't silently
    // re-select the same account on the next "Continue with Google" tap —
    // matches the mental model of "log out" the phone-OTP flow already has.
    await _googleSignIn?.signOut();
  }

  bool get isLoggedIn => supabase.auth.currentSession != null;
  String? get customerId => supabase.auth.currentUser?.id;
  String? get phone => supabase.auth.currentUser?.phone;
  String? get email => supabase.auth.currentUser?.email;
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
