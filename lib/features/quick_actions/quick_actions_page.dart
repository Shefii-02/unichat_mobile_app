import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:unichat_mobile_app/core/nav/app_modules.dart';
import 'package:unichat_mobile_app/core/theme/app_theme.dart';

/// The full app catalogue — search, one-tap shortcuts and every module tile,
/// grouped the same way the web app's 25-module blueprint is. This used to be
/// the Home tab; Home itself is now a day-to-day CRM/HRMS dashboard and links
/// in here for "everything else".
class QuickActionsPage extends StatelessWidget {
  const QuickActionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Quick Actions')),
      body: CustomScrollView(
        slivers: [
          const SliverToBoxAdapter(child: SizedBox(height: 8)),
          const SliverToBoxAdapter(child: _SearchBar()),
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
          const SliverToBoxAdapter(child: _QuickActions()),
          const SliverToBoxAdapter(child: SizedBox(height: 8)),
          ..._moduleGroups(context),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }

  List<Widget> _moduleGroups(BuildContext context) {
    final out = <Widget>[];
    for (final group in AppModules.groupsWithContent) {
      final mods = AppModules.visibleFor(group);
      out.add(SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 12),
          child: Text(
            group.label,
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: 0.2),
          ),
        ),
      ));
      out.add(SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
            childAspectRatio: 0.82,
          ),
          delegate: SliverChildBuilderDelegate(
            (_, i) => _ModuleTile(module: mods[i]),
            childCount: mods.length,
          ),
        ),
      ));
    }
    return out;
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: GestureDetector(
        onTap: () => context.push('/contacts'),
        child: Container(
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: context.altSurface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: context.lineColor),
          ),
          child: Row(
            children: [
              Icon(Icons.search_rounded, color: context.mutedColor, size: 20),
              const SizedBox(width: 10),
              Text('Search contacts, chats, leads…',
                  style: TextStyle(color: context.mutedColor, fontSize: 14)),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions();

  static const _actions = [
    (Icons.add_comment_rounded, 'New chat', '/chats'),
    (Icons.person_add_alt_1_rounded, 'New lead', '/leads'),
    (Icons.campaign_rounded, 'Broadcast', '/message-sender'),
    (Icons.qr_code_scanner_rounded, 'Scan', '/sessions'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: _actions.map((a) {
          return Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => context.push(a.$3),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(a.$1,
                          color: theme.colorScheme.primary, size: 22),
                    ),
                    const SizedBox(height: 6),
                    Text(a.$2,
                        style: const TextStyle(
                            fontSize: 11.5, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _ModuleTile extends StatelessWidget {
  const _ModuleTile({required this.module});
  final AppModule module;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tint = module.color ?? theme.colorScheme.primary;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => context.push(module.route),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: tint.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(module.icon, color: tint, size: 24),
            ),
            const SizedBox(height: 7),
            Text(
              module.title,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 11.5, fontWeight: FontWeight.w600, height: 1.15),
            ),
          ],
        ),
      ),
    );
  }
}
