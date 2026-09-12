import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:unichat_mobile_app/core/nav/app_modules.dart';
import 'package:unichat_mobile_app/features/auth/data/models/user_model.dart';
import 'package:unichat_mobile_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:unichat_mobile_app/features/modules/_shared.dart';
import 'package:unichat_mobile_app/features/modules/module_providers.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).value;
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(authProvider);
            ref.invalidate(analyticsOverviewProvider);
          },
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _Header(user: user)),
              const SliverToBoxAdapter(child: SizedBox(height: 16)),
              SliverToBoxAdapter(child: _SearchBar()),
              const SliverToBoxAdapter(child: SizedBox(height: 16)),
              const SliverToBoxAdapter(child: _StatsStrip()),
              const SliverToBoxAdapter(child: SizedBox(height: 12)),
              const SliverToBoxAdapter(child: _QuickActions()),
              const SliverToBoxAdapter(child: SizedBox(height: 8)),
              ..._moduleGroups(context),
              const SliverToBoxAdapter(child: SizedBox(height: 32)),
            ],
          ),
        ),
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

class _Header extends StatelessWidget {
  const _Header({required this.user});
  final UserModel? user;

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = (user?.name ?? '').split(' ').first;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 0),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$_greeting${name.isEmpty ? '' : ', $name'}',
                    style: TextStyle(color: context.mutedColor, fontSize: 13)),
                const SizedBox(height: 2),
                Text(
                  user?.companyName ?? 'Flowexa',
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => context.push('/notifications'),
            icon: const Icon(Icons.notifications_none_rounded),
          ),
          GestureDetector(
            onTap: () => context.push('/settings'),
            child: CircleAvatar(
              radius: 20,
              backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.15),
              backgroundImage: (user?.avatar != null && user!.avatar!.isNotEmpty)
                  ? NetworkImage(user!.avatar!)
                  : null,
              child: (user?.avatar == null || user!.avatar!.isEmpty)
                  ? Text(
                      (user?.name.isNotEmpty ?? false)
                          ? user!.name[0].toUpperCase()
                          : '?',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.primary),
                    )
                  : null,
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }
}

class _StatsStrip extends ConsumerWidget {
  const _StatsStrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(analyticsOverviewProvider);
    return async.maybeWhen(
      orElse: () => const SizedBox(height: 0),
      data: (d) {
        final chips = <(String, String)>[
          ('Messages', compact(d['messages_sent'] ?? d['total_messages'])),
          ('Leads', compact(d['leads'] ?? d['total_leads'])),
          ('Contacts', compact(d['contacts'] ?? d['total_contacts'])),
          ('Campaigns', compact(d['campaigns'] ?? d['total_campaigns'])),
        ].where((c) => c.$2 != '0').toList();
        if (chips.isEmpty) return const SizedBox(height: 0);
        return SizedBox(
          height: 66,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: chips.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) {
              final theme = Theme.of(context);
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: context.lineColor),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(chips[i].$2,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800)),
                    Text(chips[i].$1,
                        style: TextStyle(
                            color: context.mutedColor, fontSize: 11.5)),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _SearchBar extends StatelessWidget {
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
