import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:unichat_mobile_app/core/theme/mockup_palette.dart';
import 'package:unichat_mobile_app/core/constants/api_constants.dart';
import 'package:unichat_mobile_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:unichat_mobile_app/features/modules/_shared.dart';
import 'package:unichat_mobile_app/features/modules/module_providers.dart';

/// Profile screen: avatar/name/role, a few at-a-glance stats (this month's sales, team
/// rank, day streak — all real, drawn from the same aggregates the Home/Target screens
/// use), and menu groups for account/preferences, including logout.
class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final user = ref.watch(authProvider).value;
    final dash = ref.watch(dashboardMeProvider).maybeWhen(orElse: () => null, data: (d) => d);
    final sales = ref.watch(salesMeProvider(null)).maybeWhen(orElse: () => null, data: (d) => d);

    final name = user?.name ?? '';
    final initials = name.trim().isEmpty
        ? '?'
        : name.trim().split(' ').where((w) => w.isNotEmpty).map((w) => w[0].toUpperCase()).take(2).join();
    final rank = (dash?['rank'] is Map) ? (dash!['rank'] as Map) : const {};
    final streak = (dash?['streak'] is Map) ? (dash!['streak'] as Map) : const {};

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(authProvider);
            ref.invalidate(dashboardMeProvider);
            ref.invalidate(salesMeProvider);
          },
          child: ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              Container(
                width: double.infinity,
                color: M.heroBg,
                padding: const EdgeInsets.fromLTRB(18, 20, 18, 24),
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 36,
                      backgroundColor: M.heroAvatarBg,
                      backgroundImage: resolveStorageUrl(user?.avatar) != null
                          ? NetworkImage(resolveStorageUrl(user!.avatar)!)
                          : null,
                      child: (user?.avatar == null || user!.avatar!.isEmpty)
                          ? Text(initials, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 20, color: M.heroAvatarText))
                          : null,
                    ),
                    const SizedBox(height: 10),
                    Text(name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(_titleCase(user?.role ?? ''), style: const TextStyle(fontSize: 12, color: M.heroMuted)),
                    ),
                    if ((user?.companyName ?? '').isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(top: 10),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                        child: Text(user!.companyName!, style: const TextStyle(fontSize: 11, color: Colors.white)),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: _StatTile(
                        value: sales?['achieved'] != null ? '₹${compact(sales!['achieved'])}' : '—',
                        label: 'This month',
                        tint: tintGreen,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _StatTile(
                        value: rank['position'] != null ? '#${rank['position']}' : '—',
                        label: 'Team rank',
                        tint: tintAmber,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _StatTile(
                        value: '${streak['days'] ?? 0}',
                        label: 'Day streak',
                        tint: tintLavender,
                      ),
                    ),
                  ],
                ),
              ),
              _MenuGroup(
                label: 'Account',
                items: [
                  _MenuItem(Icons.person_outline_rounded, 'Personal details', onTap: () => context.push('/edit-profile')),
                  _MenuItem(Icons.folder_outlined, 'Documents', onTap: () => _comingSoon(context)),
                  _MenuItem(Icons.event_available_outlined, 'Leave', onTap: () => context.push('/hr')),
                  _MenuItem(Icons.devices_rounded, 'Linked devices', onTap: () => context.push('/devices')),
                ],
              ),
              _MenuGroup(
                label: 'Preferences',
                items: [
                  _MenuItem(Icons.settings_outlined, 'Settings', onTap: () => context.push('/settings')),
                  _MenuItem(Icons.notifications_none_rounded, 'Notifications', onTap: () => context.push('/notifications')),
                  _MenuItem(Icons.headset_mic_outlined, 'Help and support', onTap: () => _comingSoon(context)),
                  _MenuItem(Icons.logout_rounded, 'Log out', danger: true,
                      onTap: () => ref.read(authProvider.notifier).logout()),
                ],
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  static void _comingSoon(BuildContext context) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Coming soon.')));
  }

  static String _titleCase(String s) =>
      s.isEmpty ? s : s.split('_').map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}').join(' ');
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.value, required this.label, required this.tint});
  final String value;
  final String label;
  final Tint tint;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: BoxDecoration(color: tint.$1, borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: tint.$2)),
          Text(label, style: TextStyle(fontSize: 9, color: tint.$3)),
        ],
      ),
    );
  }
}

class _MenuItem {
  const _MenuItem(this.icon, this.label, {required this.onTap, this.danger = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;
}

class _MenuGroup extends StatelessWidget {
  const _MenuGroup({required this.label, required this.items});
  final String label;
  final List<_MenuItem> items;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: Text(label, style: TextStyle(fontSize: 11, color: context.mutedColor)),
          ),
          Container(
            decoration: BoxDecoration(color: context.altSurface, borderRadius: BorderRadius.circular(12)),
            child: Column(
              children: [
                for (int i = 0; i < items.length; i++)
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: items[i].onTap,
                      borderRadius: BorderRadius.vertical(
                        top: i == 0 ? const Radius.circular(12) : Radius.zero,
                        bottom: i == items.length - 1 ? const Radius.circular(12) : Radius.zero,
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                        decoration: BoxDecoration(
                          border: i < items.length - 1 ? Border(bottom: BorderSide(color: context.lineColor)) : null,
                        ),
                        child: Row(
                          children: [
                            Icon(items[i].icon, size: 18, color: items[i].danger ? M.redMuted : context.mutedColor),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(items[i].label,
                                  style: TextStyle(fontSize: 13, color: items[i].danger ? M.redMuted : null)),
                            ),
                            if (!items[i].danger)
                              Icon(Icons.chevron_right_rounded, size: 18, color: context.mutedColor),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
