import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../services/auth_service.dart'; // AuthService, authServiceProvider, GoogleSignInCancelled

/// First step of phone+OTP login. Only collects a 10-digit Indian mobile
/// number and asks Supabase Auth to text a 6-digit code to it — no password,
/// nothing else. This intentionally replaces the old website's "type any
/// phone number to see anyone's orders" pattern: nothing here is trusted
/// until the OTP step proves the person actually holds that phone.
class PhoneEntryScreen extends ConsumerStatefulWidget {
  const PhoneEntryScreen({super.key});

  @override
  ConsumerState<PhoneEntryScreen> createState() => _PhoneEntryScreenState();
}

class _PhoneEntryScreenState extends ConsumerState<PhoneEntryScreen> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _sending = false;
  bool _googleSigningIn = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String? _validate(String? v) {
    final digits = (v ?? '').trim();
    if (digits.length != 10) return 'Enter a valid 10-digit mobile number';
    if (!RegExp(r'^[6-9]\d{9}$').hasMatch(digits)) {
      return 'Enter a valid Indian mobile number';
    }
    return null;
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final e164 = '+91${_controller.text.trim()}';
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await ref.read(authServiceProvider).sendOtp(e164);
      if (!mounted) return;
      context.push('/otp', extra: e164);
    } catch (e) {
      setState(() => _error = 'Could not send OTP. Please check the number and try again.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _continueWithGoogle() async {
    setState(() {
      _googleSigningIn = true;
      _error = null;
    });
    try {
      await ref.read(authServiceProvider).signInWithGoogle();
      if (!mounted) return;
      // Successful login fires onAuthStateChange, which the router already
      // listens to — same landing behaviour as after OTP verification.
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/home');
      }
    } on GoogleSignInCancelled {
      // Person backed out of the account picker — not an error, no message.
    } catch (e) {
      setState(() => _error = 'Could not sign in with Google. Please try again.');
    } finally {
      if (mounted) setState(() => _googleSigningIn = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Log in')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.bolt_rounded, size: 56, color: AppColors.brand),
                const SizedBox(height: 16),
                const Text(
                  'Enter your mobile number',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.ink),
                ),
                const SizedBox(height: 6),
                const Text(
                  "We'll send you a one-time code by SMS to verify it's you — "
                  'no password needed.',
                  style: TextStyle(color: AppColors.muted, fontSize: 14),
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _controller,
                  keyboardType: TextInputType.phone,
                  autofocus: true,
                  maxLength: 10,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: 1),
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  validator: _validate,
                  decoration: InputDecoration(
                    counterText: '',
                    prefixIcon: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Text('+91', style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.ink)),
                    ),
                    prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
                    hintText: '98765 43210',
                  ),
                  onFieldSubmitted: (_) => _submit(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
                ],
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _sending ? null : _submit,
                  child: _sending
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                        )
                      : const Text('Send OTP'),
                ),
                const SizedBox(height: 16),
                const Text(
                  'By continuing, you agree to receive an SMS with a verification code. '
                  'Standard rates may apply.',
                  style: TextStyle(color: AppColors.muted, fontSize: 12),
                ),
                const SizedBox(height: 24),
                Row(
                  children: const [
                    Expanded(child: Divider(color: AppColors.line)),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Text('OR', style: TextStyle(color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w700)),
                    ),
                    Expanded(child: Divider(color: AppColors.line)),
                  ],
                ),
                const SizedBox(height: 20),
                OutlinedButton(
                  onPressed: _googleSigningIn ? null : _continueWithGoogle,
                  child: _googleSigningIn
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.ink),
                        )
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // A plain glyph rather than Google's actual "G"
                            // mark — swap in the official asset later if
                            // you want pixel-perfect branding (Google's
                            // button guidelines have the downloadable SVGs).
                            Icon(Icons.g_mobiledata_rounded, size: 26),
                            SizedBox(width: 8),
                            Text('Continue with Google'),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
