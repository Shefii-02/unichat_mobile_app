import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:unichat_mobile_app/core/nav/app_modules.dart';
import 'package:unichat_mobile_app/core/theme/app_theme.dart';
import 'package:unichat_mobile_app/features/auth/presentation/providers/auth_provider.dart';

class MorePage extends ConsumerWidget {
  const MorePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final user = ref.watch(authProvider).value;

    return Scaffold(
      appBar: AppBar(title: const Text('All features')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          for (final group in AppModules.groupsWithContent) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
              child: Text(group.label,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
            ),
            ...AppModules.visibleFor(group).map(
              (m) => ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: (m.color ?? theme.colorScheme.primary)
                        .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(m.icon,
                      size: 20, color: m.color ?? theme.colorScheme.primary),
                ),
                title: Text(m.title),
                subtitle: m.subtitle != null ? Text(m.subtitle!) : null,
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push(m.route),
              ),
            ),
          ],
          const Divider(height: 32),
          ListTile(
            leading: const Icon(Icons.logout_rounded, color: AppPalette.danger),
            title: const Text('Sign out',
                style: TextStyle(color: AppPalette.danger)),
            subtitle: user != null ? Text(user.email ?? user.name) : null,
            onTap: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('Sign out?'),
                  content: const Text(
                      'This unlinks the device. You can link it again with a QR code or PIN.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel')),
                    FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Sign out')),
                  ],
                ),
              );
              if (ok == true) {
                await ref.read(authProvider.notifier).logout(clearAppLock: true);
              }
            },
          ),
        ],
      ),
    );
  }
}
