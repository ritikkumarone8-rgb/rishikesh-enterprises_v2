import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../services/auth_service.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loggedIn = ref.watch(isLoggedInProvider);
    final phone = ref.watch(authServiceProvider).phone;

    return Scaffold(
      appBar: AppBar(title: const Text('Profile'), automaticallyImplyLeading: false),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.line),
            ),
            child: Row(
              children: [
                const CircleAvatar(radius: 26, backgroundColor: AppColors.brand, child: Icon(Icons.person, color: Colors.white)),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        loggedIn ? (phone ?? 'Signed in') : 'You are not logged in',
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.ink),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        loggedIn ? 'Rishikesh Enterprises customer' : 'Log in to view your orders and addresses',
                        style: const TextStyle(fontSize: 12, color: AppColors.muted),
                      ),
                    ],
                  ),
                ),
                if (!loggedIn)
                  ElevatedButton(
                    onPressed: () => context.push('/login'),
                    style: ElevatedButton.styleFrom(minimumSize: const Size(0, 36), padding: const EdgeInsets.symmetric(horizontal: 16)),
                    child: const Text('Log in'),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _MenuTile(
            icon: Icons.receipt_long_outlined,
            label: 'My Orders',
            onTap: () => context.push('/orders'),
          ),
          _MenuTile(
            icon: Icons.location_on_outlined,
            label: 'Saved Addresses',
            onTap: () => context.push('/profile/addresses'),
          ),
          _MenuTile(
            icon: Icons.storefront_outlined,
            label: 'About Rishikesh Enterprises',
            onTap: () => _showAbout(context),
          ),
          _MenuTile(
            icon: Icons.call_outlined,
            label: 'Contact / Support',
            onTap: () => _showAbout(context),
          ),
          if (loggedIn) ...[
            const SizedBox(height: 8),
            _MenuTile(
              icon: Icons.logout,
              label: 'Log out',
              danger: true,
              onTap: () async {
                await ref.read(authServiceProvider).signOut();
                if (context.mounted) context.go('/home');
              },
            ),
          ],
        ],
      ),
    );
  }

  void _showAbout(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Rishikesh Enterprises'),
        content: const Text(
          'Authorized Havells dealer for electricals, wiring, switches, fans, lighting and more.\n\n'
          'Hajipur, Vaishali, Bihar\n\n'
          'For support, please call the store during business hours.',
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;
  const _MenuTile({required this.icon, required this.label, required this.onTap, this.danger = false});

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppColors.danger : AppColors.ink;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: Icon(icon, color: danger ? AppColors.danger : AppColors.brand),
        title: Text(label, style: TextStyle(fontWeight: FontWeight.w700, color: color)),
        trailing: const Icon(Icons.chevron_right, color: AppColors.muted),
        onTap: onTap,
      ),
    );
  }
}
