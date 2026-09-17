import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:unichat_mobile_app/core/constants/app_colors.dart';
import 'package:unichat_mobile_app/core/network/dio_client.dart';
import 'package:unichat_mobile_app/core/utils/format_utils.dart';
import 'package:unichat_mobile_app/core/widgets/app_avatar.dart';
import 'package:unichat_mobile_app/features/auth/presentation/providers/auth_provider.dart';

// ── Dashboard stats (fetched from real working endpoints) ─────────────────────
final dashboardStatsProvider = FutureProvider<Map<String, int>>((ref) async {
  int conversations = 0, leads = 0, contacts = 0, campaigns = 0;
  await Future.wait([
    DioClient.laravelDio.get('/conversations').then((r) {
      final d = r.data as Map<String, dynamic>;
      conversations = (d['total'] as int?) ??
          (d['conversations'] as List?)?.length ?? 0;
    }).catchError((_) {}),
    DioClient.laravelDio
        .get('/leads', queryParameters: {'per_page': 1}).then((r) {
      final d = r.data as Map<String, dynamic>;
      leads = (d['total'] as int?) ?? (d['meta']?['total'] as int?) ?? 0;
    }).catchError((_) {}),
    DioClient.laravelDio
        .get('/contacts', queryParameters: {'per_page': 1}).then((r) {
      final d = r.data as Map<String, dynamic>;
      contacts = (d['total'] as int?) ?? 0;
    }).catchError((_) {}),
    DioClient.laravelDio
        .get('/campaigns', queryParameters: {'per_page': 1}).then((r) {
      final d = r.data as Map<String, dynamic>;
      campaigns = (d['total'] as int?) ??
          (d['data'] as List?)?.length ?? 0;
    }).catchError((_) {}),
  ]);
  return {
    'conversations': conversations,
    'leads': leads,
    'contacts': contacts,
    'campaigns': campaigns,
  };
});

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user       = ref.watch(authProvider).value;
    final statsAsync = ref.watch(dashboardStatsProvider);
    final greeting   = FormatUtils.greeting();
    final firstName  = user?.name.split(' ').first ?? 'there';

    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(dashboardStatsProvider),
        child: CustomScrollView(
          slivers: [
            _buildSliverAppBar(context, ref, greeting, firstName, user?.name),
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  _StatsSection(statsAsync: statsAsync),
                  const SizedBox(height: 20),
                  _sectionHeader('Quick Actions'),
                  const SizedBox(height: 12),
                  const _QuickActionsGrid(),
                  const SizedBox(height: 20),
                  _sectionHeader('Pipeline Overview'),
                  const SizedBox(height: 12),
                  const _PipelineCard(),
                  const SizedBox(height: 20),
                  _sectionHeader('Recent Activity'),
                  const SizedBox(height: 8),
                  const _RecentActivityCard(),
                  const SizedBox(height: 24),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String title) => Text(
        title,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
          letterSpacing: 0.1,
        ),
      );

  SliverAppBar _buildSliverAppBar(
    BuildContext context,
    WidgetRef ref,
    String greeting,
    String firstName,
    String? fullName,
  ) {
    return SliverAppBar(
      expandedHeight: 130,
      floating: false,
      pinned: true,
      backgroundColor: AppColors.primaryDark,
      actions: [
        IconButton(
          icon: const Icon(Icons.search, color: Colors.white),
          onPressed: () {},
        ),
        IconButton(
          icon: const Icon(Icons.notifications_outlined, color: Colors.white),
          onPressed: () => context.push('/notifications'),
        ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.primaryDark, AppColors.primary],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$greeting, $firstName! 👋',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 2),
                            const Text(
                              'UniChat CRM Dashboard',
                              style: TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: () => context.push('/settings'),
                        child: AppAvatar(name: fullName, size: 42),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Stat cards ────────────────────────────────────────────────────────────────
class _StatsSection extends StatelessWidget {
  final AsyncValue<Map<String, int>> statsAsync;
  const _StatsSection({required this.statsAsync});

  @override
  Widget build(BuildContext context) {
    final stats = statsAsync.value ?? {};
    final cards = <_StatCardData>[
      _StatCardData(emoji: '💬', label: 'Chats',     value: stats['conversations'], color: AppColors.info,         route: '/wa-chat/chats'),
      _StatCardData(emoji: '🎯', label: 'Leads',     value: stats['leads'],         color: AppColors.scoreWarm,   route: '/leads'),
      _StatCardData(emoji: '👥', label: 'Contacts',  value: stats['contacts'],      color: AppColors.primary,      route: '/contacts'),
      _StatCardData(emoji: '📢', label: 'Campaigns', value: stats['campaigns'],     color: AppColors.stagePayment, route: '/campaigns'),
    ];

    return Row(
      children: List.generate(cards.length, (i) => Expanded(
        child: Padding(
          padding: EdgeInsets.only(left: i == 0 ? 0 : 4, right: i == cards.length - 1 ? 0 : 4),
          child: _StatCardWidget(data: cards[i]),
        ),
      )),
    );
  }
}

class _StatCardData {
  final String emoji, label, route;
  final int? value;
  final Color color;
  const _StatCardData({
    required this.emoji,
    required this.label,
    required this.value,
    required this.color,
    required this.route,
  });
}

class _StatCardWidget extends StatelessWidget {
  final _StatCardData data;
  const _StatCardWidget({required this.data});

  @override
  Widget build(BuildContext context) {
    final shellRoutes = {'/wa-chat/chats', '/leads', '/contacts'};
    return GestureDetector(
      onTap: () => shellRoutes.contains(data.route)
          ? context.go(data.route)
          : context.push(data.route),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: data.color.withAlpha(30),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(data.emoji, style: const TextStyle(fontSize: 22)),
            const SizedBox(height: 6),
            Text(
              data.value != null ? '${data.value}' : '—',
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w900, color: data.color),
            ),
            const SizedBox(height: 2),
            Text(
              data.label,
              style: const TextStyle(
                  fontSize: 10,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Quick Actions grid ────────────────────────────────────────────────────────
class _QuickActionsGrid extends StatelessWidget {
  const _QuickActionsGrid();

  static const _actions = [
    _ActionItem(Icons.chat_bubble_outline, 'New Chat',    '/wa-chat/chats',  AppColors.primary,       true),
    _ActionItem(Icons.person_add_outlined, 'Add Lead',    '/leads',          AppColors.scoreWarm,     true),
    _ActionItem(Icons.campaign_outlined,   'Campaign',    '/campaigns',      AppColors.stagePayment,  false),
    _ActionItem(Icons.send_outlined,       'Broadcast',   '/message-sender', AppColors.accent,        false),
    _ActionItem(Icons.bar_chart_outlined,  'Reports',     '/reports',        AppColors.stageEngaged,  false),
    _ActionItem(Icons.settings_outlined,   'Settings',    '/settings',       AppColors.textSecondary, false),
  ];

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 1.15,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: _actions.length,
      itemBuilder: (_, i) {
        final a = _actions[i];
        return Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: () => a.inShell ? context.go(a.route) : context.push(a.route),
            borderRadius: BorderRadius.circular(14),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withAlpha(10),
                      blurRadius: 6,
                      offset: const Offset(0, 2)),
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: a.color.withAlpha(20),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(a.icon, color: a.color, size: 22),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    a.label,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ActionItem {
  final IconData icon;
  final String label, route;
  final Color color;
  final bool inShell;
  const _ActionItem(this.icon, this.label, this.route, this.color, this.inShell);
}

// ── Pipeline chart ────────────────────────────────────────────────────────────
class _PipelineCard extends StatelessWidget {
  const _PipelineCard();

  @override
  Widget build(BuildContext context) {
    const stages = [
      ('New',        0.9, AppColors.stageNew,        '45'),
      ('Engaged',    0.6, AppColors.stageEngaged,    '30'),
      ('Interested', 0.4, AppColors.stageInterested, '20'),
      ('Payment',    0.3, AppColors.stagePayment,    '15'),
      ('Converted',  0.2, AppColors.stageConverted,  '10'),
    ];

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: stages.map((s) {
            final (label, pct, color, count) = s;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  SizedBox(
                    width: 74,
                    child: Text(label,
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textSecondary)),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: pct,
                        backgroundColor: AppColors.bgGray,
                        valueColor: AlwaysStoppedAnimation(color),
                        minHeight: 8,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 28,
                    child: Text(count,
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary)),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

// ── Recent Activity ───────────────────────────────────────────────────────────
class _RecentActivityCard extends StatelessWidget {
  const _RecentActivityCard();

  @override
  Widget build(BuildContext context) {
    const items = [
      (Icons.person_add,   AppColors.primary,         'New lead assigned to you',   '2m ago'),
      (Icons.check_circle, AppColors.stageConverted,  'Lead converted — Ahmed Ali', '1h ago'),
      (Icons.smart_toy,    AppColors.accent,            'AI took over conversation',  '2h ago'),
      (Icons.campaign,     AppColors.stagePayment,      'Campaign "Ramadan" sent',    '3h ago'),
      (Icons.star,         AppColors.scoreWarm,         'Contact rated ★★★★★',        '5h ago'),
    ];

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Column(
        children: List.generate(items.length, (i) {
          final (icon, color, title, time) = items[i];
          return Column(
            children: [
              ListTile(
                leading: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                      color: color.withAlpha(20),
                      borderRadius: BorderRadius.circular(10)),
                  child: Icon(icon, color: color, size: 20),
                ),
                title: Text(title,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
                trailing: Text(time,
                    style:
                        const TextStyle(fontSize: 11, color: AppColors.textLight)),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                dense: true,
              ),
              if (i < items.length - 1)
                const Divider(height: 1, indent: 70, endIndent: 16),
            ],
          );
        }),
      ),
    );
  }
}
