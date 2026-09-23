import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';

class OrderSuccessScreen extends StatelessWidget {
  final String orderCode;
  const OrderSuccessScreen({super.key, required this.orderCode});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 84,
                  height: 84,
                  decoration: const BoxDecoration(color: AppColors.ok, shape: BoxShape.circle),
                  child: const Icon(Icons.check, color: Colors.white, size: 48),
                ),
                const SizedBox(height: 20),
                const Text('Order placed!', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.ink)),
                const SizedBox(height: 8),
                Text('Order #$orderCode', style: const TextStyle(fontSize: 15, color: AppColors.muted, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                const Text(
                  "We'll notify you as your order is confirmed and prepared.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.muted),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => context.go('/order/$orderCode'),
                    child: const Text('View order'),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => context.go('/home'),
                    child: const Text('Continue shopping'),
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
