import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:unichat_mobile_app/core/constants/app_colors.dart';

class MorePage extends StatelessWidget {
  const MorePage({super.key});

  static const _items = [
    _MoreItem('📊', 'Reports',      '/reports'),
    _MoreItem('🌊', 'Flow Builder', '/flow-builder'),
    _MoreItem('🎯', 'Templates',    '/templates'),
    _MoreItem('📱', 'WA Sessions',  '/sessions'),
    _MoreItem('🔑', 'OTP Service',  '/otp-service'),
    _MoreItem('🤖', 'AI Agent',     '/ai-agent-test'),
    _MoreItem('👥', 'Staff',        '/staff'),
    _MoreItem('📚', 'Knowledge',    '/knowledge-base'),
    _MoreItem('📨', 'Msg Sender',   '/message-sender'),
    _MoreItem('📤', 'Export',       '/export'),
    _MoreItem('📁', 'Media',        '/media-library'),
    _MoreItem('⚙️', 'Settings',    '/settings'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          childAspectRatio: 1.1,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: _items.length,
        itemBuilder: (_, i) {
          final item = _items[i];
          return InkWell(
            onTap: () => context.push(item.route),
            borderRadius: BorderRadius.circular(14),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [BoxShadow(color: Colors.black.withAlpha(12), blurRadius: 6, offset: const Offset(0, 2))],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(item.emoji, style: const TextStyle(fontSize: 30)),
                  const SizedBox(height: 6),
                  Text(item.label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _MoreItem {
  const _MoreItem(this.emoji, this.label, this.route);
  final String emoji;
  final String label;
  final String route;
}
