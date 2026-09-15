import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:unichat_mobile_app/core/constants/app_colors.dart';
import 'package:unichat_mobile_app/core/widgets/app_avatar.dart';
import 'package:unichat_mobile_app/features/auth/presentation/providers/auth_provider.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).value;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          if (user != null)
            Container(
              padding: const EdgeInsets.all(20),
              color: AppColors.primary.withAlpha(10),
              child: Row(
                children: [
                  AppAvatar(name: user.name, size: 56),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(user.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                        Text(user.role.toUpperCase(), style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                        Text(user.companyName ?? '', style: const TextStyle(color: AppColors.textLight, fontSize: 12)),
                      ],
                    ),
                  ),
                  IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () {}),
                ],
              ),
            ),

          const SizedBox(height: 8),

          _section('Appearance', [
            _tile(Icons.dark_mode_outlined, 'Dark Mode', trailing: const Icon(Icons.chevron_right)),
            _tile(Icons.language, 'Language', subtitle: 'English', trailing: const Icon(Icons.chevron_right)),
          ]),

          _section('Notifications', [
            _toggleTile(Icons.notifications_outlined, 'New Lead Alerts', true, (_) {}),
            _toggleTile(Icons.smart_toy_outlined, 'AI Handoff Offers', true, (_) {}),
            _toggleTile(Icons.timer_outlined, 'SLA Breach Alerts', true, (_) {}),
            _toggleTile(Icons.campaign_outlined, 'Campaign Updates', true, (_) {}),
          ]),

          _section('Security', [
            _tile(Icons.lock_outline, 'Change Password', trailing: const Icon(Icons.chevron_right)),
            _tile(Icons.devices_rounded, 'Linked Devices',
                subtitle: 'Manage devices signed in to this account',
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/devices')),
            _toggleTile(Icons.fingerprint, 'Biometric Login', false, (_) {}),
          ]),

          _section('About', [
            _tile(Icons.info_outline, 'Version', subtitle: '1.0.0'),
            _tile(Icons.support_agent, 'Support', trailing: const Icon(Icons.chevron_right)),
            _tile(Icons.privacy_tip_outlined, 'Privacy Policy', trailing: const Icon(Icons.chevron_right)),
          ]),

          const SizedBox(height: 16),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ElevatedButton.icon(
              onPressed: () => _confirmLogout(context, ref),
              icon: const Icon(Icons.logout),
              label: const Text('Logout'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _section(String title, List<Widget> tiles) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textLight, letterSpacing: 0.8)),
        ),
        ...tiles,
        const Divider(height: 1),
      ],
    );
  }

  Widget _tile(IconData icon, String label, {String? subtitle, Widget? trailing, VoidCallback? onTap}) {
    return ListTile(
      leading: Icon(icon, color: AppColors.textSecondary, size: 22),
      title: Text(label, style: const TextStyle(fontSize: 14)),
      subtitle: subtitle != null ? Text(subtitle, style: const TextStyle(fontSize: 12, color: AppColors.textLight)) : null,
      trailing: trailing,
      onTap: onTap ?? () {},
    );
  }

  Widget _toggleTile(IconData icon, String label, bool value, ValueChanged<bool> onChanged) {
    return ListTile(
      leading: Icon(icon, color: AppColors.textSecondary, size: 22),
      title: Text(label, style: const TextStyle(fontSize: 14)),
      trailing: Switch(value: value, onChanged: onChanged, activeThumbColor: AppColors.primary),
    );
  }

  void _confirmLogout(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Logout?'),
        content: const Text('You will be signed out and redirected to the login screen.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              ref.read(authProvider.notifier).logout();
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
  }
}
