import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:unichat_mobile_app/core/network/api.dart';
import 'package:unichat_mobile_app/core/theme/app_theme.dart';
import 'package:unichat_mobile_app/features/home/stats_charts.dart';
import 'package:unichat_mobile_app/features/modules/_shared.dart';
import 'package:unichat_mobile_app/features/modules/module_providers.dart';

// Account-type specific Home panels. Each one reads its own API, so a Sales user, an HR
// user and an Accounts user get genuinely different data — not the same screen with
// blocks hidden. Home decides which panels to mount from the user's access sections
// (see home_page.dart); a panel whose API 403s/fails just collapses.

final _accountsDashProvider = FutureProvider(
    (ref) => Api.one('/accounts/dashboard'));
final _hrTodayProvider = FutureProvider(
    (ref) => Api.list('/hr/attendance', query: {'per_page': 300}));
final _recentCampaignsProvider = FutureProvider(
    (ref) => Api.list('/campaigns', query: {'per_page': 5}));
final _staffCountProvider = FutureProvider(
    (ref) => Api.list('/staff', query: {'per_page': 100}));

num _n(Object? v) => v is num ? v : (num.tryParse('${v ?? ''}') ?? 0);
String _money(Object? v) => '₹${compact(v)}';

class _Tile {
  const _Tile(this.label, this.value, this.icon, this.color);
  final String label, value;
  final IconData icon;
  final Color color;
}

/// Rounded card with a tinted icon header + a responsive grid of stat tiles.
class _PanelCard extends StatelessWidget {
  const _PanelCard({
    required this.title,
    required this.icon,
    required this.accent,
    required this.tiles,
    this.footer,
    this.onTap,
  });
  final String title;
  final IconData icon;
  final Color accent;
  final List<_Tile> tiles;
  final Widget? footer;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Material(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: context.lineColor),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [accent.withOpacity(0.10), accent.withOpacity(0.0)],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: accent.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(icon, color: accent, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(title,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w800)),
                  ),
                  if (onTap != null)
                    Icon(Icons.chevron_right_rounded, color: context.mutedColor),
                ]),
                const SizedBox(height: 14),
                LayoutBuilder(builder: (context, c) {
                  final w = (c.maxWidth - 10) / 2;
                  return Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final t in tiles)
                        SizedBox(
                          width: w,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: t.color.withOpacity(0.10),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Row(children: [
                              Icon(t.icon, size: 18, color: t.color),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    FittedBox(
                                      fit: BoxFit.scaleDown,
                                      alignment: Alignment.centerLeft,
                                      child: Text(t.value,
                                          style: theme.textTheme.titleMedium
                                              ?.copyWith(
                                                  fontWeight: FontWeight.w800)),
                                    ),
                                    Text(t.label,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            color: context.mutedColor,
                                            fontSize: 11.5)),
                                  ],
                                ),
                              ),
                            ]),
                          ),
                        ),
                    ],
                  );
                }),
                if (footer != null) ...[const SizedBox(height: 12), footer!],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Wraps a provider so loading/403/error collapse quietly instead of leaving a hole.
Widget _guard<T>(AsyncValue<T> async, Widget Function(T d) build) =>
    async.when(
      data: build,
      loading: () => const Padding(
        padding: EdgeInsets.all(20),
        child: Center(
            child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2))),
      ),
      error: (_, __) => const SizedBox.shrink(),
    );

// ───────────────────────── Sales team ─────────────────────────

class SalesPanel extends ConsumerWidget {
  const SalesPanel({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _guard(ref.watch(analyticsOverviewProvider), (d) {
      final l = d['leads'] is Map ? d['leads'] as Map : const {};
      return _PanelCard(
        title: 'Sales team',
        icon: Icons.trending_up_rounded,
        accent: const Color(0xFF22C55E),
        onTap: () => context.push('/leads'),
        tiles: [
          _Tile('New today', compact(l['new_today']), Icons.fiber_new_rounded,
              const Color(0xFF0EA5E9)),
          _Tile('In progress', compact(l['in_progress']),
              Icons.autorenew_rounded, const Color(0xFFF59E0B)),
          _Tile('Enrolled', compact(l['enrolled']), Icons.verified_rounded,
              const Color(0xFF16A34A)),
          _Tile('Lost', compact(l['lost']), Icons.cancel_rounded,
              const Color(0xFFDC2626)),
        ],
      );
    });
  }
}

// ───────────────────────── Accounts team ─────────────────────────

class AccountsPanel extends ConsumerWidget {
  const AccountsPanel({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _guard(ref.watch(_accountsDashProvider), (d) {
      final profit = _n(d['profit']);
      return _PanelCard(
        title: 'Finance snapshot',
        icon: Icons.account_balance_rounded,
        accent: const Color(0xFFEAB308),
        onTap: () => context.push('/accounts'),
        tiles: [
          _Tile('Income', _money(d['income']), Icons.south_west_rounded,
              const Color(0xFF16A34A)),
          _Tile('Expense', _money(d['expense']), Icons.north_east_rounded,
              const Color(0xFFDC2626)),
          _Tile(profit >= 0 ? 'Profit' : 'Loss', _money(profit.abs()),
              Icons.trending_up_rounded, const Color(0xFF0EA5E9)),
          _Tile('Cash + Bank', _money(_n(d['cash']) + _n(d['bank'])),
              Icons.savings_rounded, const Color(0xFF7C3AED)),
          _Tile('Receivable', _money(d['receivable']),
              Icons.call_received_rounded, const Color(0xFF0D9488)),
          _Tile('Payable', _money(d['payable']), Icons.call_made_rounded,
              const Color(0xFFEA580C)),
        ],
      );
    });
  }
}

// ───────────────────────── HR team ─────────────────────────

class HrTeamPanel extends ConsumerWidget {
  const HrTeamPanel({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _guard(ref.watch(_hrTodayProvider), (rows) {
      final staff = ref.watch(_staffCountProvider).value?.length;
      final present = rows.where((r) => r['clock_in_at'] != null).length;
      final late = rows.where((r) => _n(r['late_minutes']) > 0).length;
      final onLeave = rows.where((r) => r['status'] == 'on_leave').length;
      final working = rows
          .where((r) => r['clock_in_at'] != null && r['clock_out_at'] == null)
          .length;
      return _PanelCard(
        title: "Team today",
        icon: Icons.groups_rounded,
        accent: const Color(0xFFEC4899),
        onTap: () => context.push('/hr/attendance-all'),
        tiles: [
          _Tile('Present', '$present${staff != null ? ' / $staff' : ''}',
              Icons.how_to_reg_rounded, const Color(0xFF16A34A)),
          _Tile('Working now', '$working', Icons.work_history_rounded,
              const Color(0xFF0EA5E9)),
          _Tile('Late', '$late', Icons.schedule_rounded,
              const Color(0xFFEA580C)),
          _Tile('On leave', '$onLeave', Icons.beach_access_rounded,
              const Color(0xFF7C3AED)),
        ],
      );
    });
  }
}

// ───────────────────────── Marketing team ─────────────────────────

class MarketingPanel extends ConsumerWidget {
  const MarketingPanel({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _guard(ref.watch(_recentCampaignsProvider), (rows) {
      final overview = ref.watch(analyticsOverviewProvider).value ?? const {};
      return _PanelCard(
        title: 'Campaigns',
        icon: Icons.campaign_rounded,
        accent: const Color(0xFFF97316),
        onTap: () => context.push('/campaigns'),
        tiles: [
          _Tile('Messages sent',
              compact(overview['messages_sent'] ?? overview['total_messages']),
              Icons.send_rounded, const Color(0xFF0EA5E9)),
          _Tile('Campaigns',
              compact(overview['campaigns'] ?? overview['total_campaigns'] ?? rows.length),
              Icons.campaign_rounded, const Color(0xFFF97316)),
        ],
        footer: rows.isEmpty
            ? null
            : Column(children: [
                for (final c in rows.take(3))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(children: [
                      Expanded(
                        child: Text('${c['name'] ?? 'Campaign'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                      ),
                      const SizedBox(width: 8),
                      _StatusPill('${c['status'] ?? ''}'),
                    ]),
                  ),
              ]),
      );
    });
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill(this.status);
  final String status;
  @override
  Widget build(BuildContext context) {
    final s = status.toLowerCase();
    final c = s.contains('complet') || s.contains('sent')
        ? const Color(0xFF16A34A)
        : s.contains('fail')
            ? const Color(0xFFDC2626)
            : const Color(0xFFF59E0B);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
          color: c.withOpacity(0.14), borderRadius: BorderRadius.circular(99)),
      child: Text(status.isEmpty ? '—' : status,
          style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }
}

// ───────────────────────── Administrators ─────────────────────────

class AdminPanel extends ConsumerWidget {
  const AdminPanel({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _guard(ref.watch(_staffCountProvider), (staff) {
      final active = staff.where((s) => s['is_active'] != false).length;
      return _PanelCard(
        title: 'Workspace',
        icon: Icons.shield_rounded,
        accent: const Color(0xFF0EA5E9),
        onTap: () => context.push('/staff'),
        tiles: [
          _Tile('Staff', '${staff.length}', Icons.badge_rounded,
              const Color(0xFF0EA5E9)),
          _Tile('Active', '$active', Icons.verified_user_rounded,
              const Color(0xFF16A34A)),
        ],
      );
    });
  }
}

// ───────────────────────── Statistics → Accounts ─────────────────────────

/// Body of the Statistics "Accounts" dropdown entry: finance chips + income-vs-expense
/// trend (last months) from GET /accounts/dashboard.
class AccountsStatsBody extends ConsumerWidget {
  const AccountsStatsBody({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _guard(ref.watch(_accountsDashProvider), (d) {
      final profit = _n(d['profit']);
      final chips = <(String, String, Color)>[
        ('Income', _money(d['income']), const Color(0xFF16A34A)),
        ('Expense', _money(d['expense']), const Color(0xFFDC2626)),
        (profit >= 0 ? 'Profit' : 'Loss', _money(profit.abs()), const Color(0xFF0EA5E9)),
        ('Cash + Bank', _money(_n(d['cash']) + _n(d['bank'])), const Color(0xFF7C3AED)),
        ('Receivable', _money(d['receivable']), const Color(0xFF0D9488)),
        ('Payable', _money(d['payable']), const Color(0xFFEA580C)),
      ];
      final rows = (d['chart'] is List ? d['chart'] as List : const []).whereType<Map>().toList();
      const mon = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      String lbl(Object? m) {
        final p = '$m'.split('-');
        final i = p.length > 1 ? (int.tryParse(p[1]) ?? 1) : 1;
        return mon[(i - 1).clamp(0, 11)];
      }
      return Column(children: [
        SizedBox(
          height: 66,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: chips.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: chips[i].$3.withOpacity(0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: chips[i].$3.withOpacity(0.25)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(chips[i].$2,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                  Text(chips[i].$1, style: TextStyle(color: context.mutedColor, fontSize: 11.5)),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
          child: Container(
            padding: const EdgeInsets.fromLTRB(8, 12, 12, 8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: context.lineColor),
            ),
            child: TrendLineChart(
              labels: [for (final r in rows) lbl(r['month'])],
              series: [
                [for (final r in rows) _n(r['income']).toDouble()],
                [for (final r in rows) _n(r['expense']).toDouble()],
              ],
              colors: const [Color(0xFF16A34A), Color(0xFFDC2626)],
              legend: const ['Income', 'Expense'],
            ),
          ),
        ),
      ]);
    });
  }
}

// ───────────────────── Statistics → Workspace / Attendance ─────────────────────

Widget _statChips(BuildContext context, List<(String, String, Color)> chips) => SizedBox(
      height: 66,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: chips.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: chips[i].$3.withOpacity(0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: chips[i].$3.withOpacity(0.25)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(chips[i].$2,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              Text(chips[i].$1, style: TextStyle(color: context.mutedColor, fontSize: 11.5)),
            ],
          ),
        ),
      ),
    );

/// Statistics → Workspace: staff counts (GET /staff).
class WorkspaceStatsBody extends ConsumerWidget {
  const WorkspaceStatsBody({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _guard(ref.watch(_staffCountProvider), (staff) {
      final active = staff.where((s) => s['is_active'] != false).length;
      return _statChips(context, [
        ('Staff', '${staff.length}', const Color(0xFF0EA5E9)),
        ('Active', '$active', const Color(0xFF16A34A)),
        ('Inactive', '${staff.length - active}', const Color(0xFFDC2626)),
      ]);
    });
  }
}

/// Statistics → Attendance: today's team attendance (GET /hr/attendance, defaults to today).
class AttendanceStatsBody extends ConsumerWidget {
  const AttendanceStatsBody({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _guard(ref.watch(_hrTodayProvider), (rows) {
      final staff = ref.watch(_staffCountProvider).value?.length;
      final present = rows.where((r) => r['clock_in_at'] != null).length;
      final working = rows.where((r) => r['clock_in_at'] != null && r['clock_out_at'] == null).length;
      final late = rows.where((r) => _n(r['late_minutes']) > 0).length;
      final onLeave = rows.where((r) => r['status'] == 'on_leave').length;
      return _statChips(context, [
        ('Present', '$present${staff != null ? ' / $staff' : ''}', const Color(0xFF16A34A)),
        ('Working now', '$working', const Color(0xFF0EA5E9)),
        ('Late', '$late', const Color(0xFFEA580C)),
        ('On leave', '$onLeave', const Color(0xFF7C3AED)),
        if (staff != null) ('Absent', '${(staff - present - onLeave).clamp(0, staff)}', const Color(0xFFDC2626)),
      ]);
    });
  }
}
