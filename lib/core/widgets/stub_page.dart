import 'package:flutter/material.dart';
import 'package:unichat_mobile_app/core/constants/app_colors.dart';

class StubPage extends StatelessWidget {
  const StubPage({super.key, required this.title, this.emoji = '🚧'});
  final String title;
  final String emoji;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 64)),
            const SizedBox(height: 16),
            Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            const SizedBox(height: 8),
            const Text('Coming soon', style: TextStyle(color: AppColors.textLight)),
          ],
        ),
      ),
    );
  }
}
