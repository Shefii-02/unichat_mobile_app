import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:unichat_mobile_app/core/nav/app_modules.dart';
import 'package:unichat_mobile_app/core/nav/hidden_modules_provider.dart';
import 'package:unichat_mobile_app/core/theme/app_theme.dart';
import 'package:unichat_mobile_app/features/auth/presentation/providers/auth_provider.dart';

class MorePage extends ConsumerWidget {
  const MorePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final user = ref.watch(authProvider).value;
    ref.watch(mobileHiddenModulesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('All features')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(authProvider);
          ref.invalidate(mobileHiddenModulesProvider);
          await ref.read(mobileHiddenModulesProvider.future);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            for (final group in AppModules.groupsWithContent) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                child: Text(
                  group.label,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: GridView(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 5,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    mainAxisExtent: 74,
                  ),
                  children: [
                    for (final m in AppModules.visibleFor(group))
                      _ModuleTile(
                        module: m,
                        color: m.color ?? theme.colorScheme.primary,
                        onTap: () => context.push(m.route),
                      ),
                  ],
                ),
              ),
            ],
            const Divider(height: 32),
            ListTile(
              leading: const Icon(
                Icons.logout_rounded,
                color: AppPalette.danger,
              ),
              title: const Text(
                'Sign out',
                style: TextStyle(color: AppPalette.danger),
              ),
              subtitle: user != null ? Text(user.email ?? user.name) : null,
              onTap: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder:
                      (_) => AlertDialog(
                        title: const Text('Sign out?'),
                        content: const Text(
                          'This unlinks the device. You can link it again with a QR code or PIN.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Cancel'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Sign out'),
                          ),
                        ],
                      ),
                );
                if (ok == true) {
                  await ref
                      .read(authProvider.notifier)
                      .logout(clearAppLock: true);
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ModuleTile extends StatelessWidget {
  const _ModuleTile({
    required this.module,
    required this.color,
    required this.onTap,
  });

  final AppModule module;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(module.icon, size: 20, color: color),
              ),
              const SizedBox(height: 6),
              Text(
                module.title.length > 10
                    ? '${module.title.substring(0, 10).trimRight()}...'
                    : module.title,
                maxLines: 1,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                textScaler: TextScaler.noScaling,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontSize: 10,
                  height: 1.15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
