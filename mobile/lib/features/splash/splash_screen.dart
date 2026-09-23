import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    // Browsing the catalogue never requires login — only checkout, order
    // history and profile do (enforced centrally in the router's
    // `redirect`). So splash always lands on /home; login is asked for
    // only at the moment it's actually needed.
    Future.delayed(const Duration(milliseconds: 900), () {
      if (mounted) context.go('/home');
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.bg,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bolt_rounded, size: 96, color: AppColors.brand),
            SizedBox(height: 12),
            Text(
              'RISHIKESH',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: AppColors.brand,
                letterSpacing: 1,
              ),
            ),
            Text(
              'ENTERPRISES',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: AppColors.brandDark,
                letterSpacing: 6,
              ),
            ),
            SizedBox(height: 6),
            Text('Hajipur · Vaishali · Bihar', style: TextStyle(color: AppColors.muted, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
