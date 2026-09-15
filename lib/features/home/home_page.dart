import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:unichat_mobile_app/core/permissions/permission_guard.dart';
import 'package:unichat_mobile_app/features/attendance/widgets/attendance_status_card.dart';
import 'package:unichat_mobile_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:unichat_mobile_app/features/modules/_shared.dart';
import 'package:unichat_mobile_app/features/modules/module_providers.dart';
import 'package:unichat_mobile_app/core/theme/mockup_palette.dart';

/// Day-to-day CRM/HRMS dashboard: sales target, attendance (clock in/out,
/// breaks), personal stats (new leads / follow-ups / streak / rank), pipeline,
/// follow-ups, today's tasks and what's next — all from one aggregate call
/// (GET /hr/dashboard/me, see DashboardController@me). The former Home content
/// (search + full module grid) now lives at [QuickActionsPage] under
/// `/quick-actions`, linked from the header here.
///
/// Colours for the hero header, attendance card, stat/pipeline/follow-up
/// tiles and the "next up" banner follow the approved product mockup exactly
/// (fixed brand palette, not the app's teal theme) — see [M] in
/// `core/theme/mockup_palette.dart`, shared with the Leads/Target/Attendance/
/// Payroll/Profile screens. Structural chrome (borders, muted/body text, the
/// "View all" links) stays on the app's theme tokens, matching how the
/// mockup itself used CSS variables for those parts.
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final canManageHr = PermissionGuard.can('hr.manage') ||
        PermissionGuard.can('hr.attendance.view_all') ||
        PermissionGuard.can('staff.view');

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(authProvider);
            ref.invalidate(analyticsOverviewProvider);
            ref.invalidate(hrAttendanceMeProvider);
            ref.invalidate(dashboardMeProvider);
            ref.invalidate(crmMyTasksProvider);
            if (canManageHr) ref.invalidate(hrTeamAttendanceTodayProvider);
          },
          child: ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              const _HeroHeader(),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: AttendanceStatusCard(),
              ),
              const _PersonalStatsStrip(),
              const _StatsStrip(),
              const _PipelineSection(),
              const _FollowUpsSection(),
              if (canManageHr) const _TeamAttendanceToday(),
              const _TodayTasks(),
              const _NextUpCard(),
            ],
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════ Hero header (greeting + sales target) ══════════════════════════

class _HeroHeader extends ConsumerWidget {
  const _HeroHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).value;
    final target = ref.watch(dashboardMeProvider).maybeWhen(
          orElse: () => null,
          data: (d) => (d['sales_target'] is Map) ? (d['sales_target'] as Map).cast<String, dynamic>() : null,
        );
    final progress = target?['progress'];
    final pct = progress != null ? (num.tryParse('$progress') ?? 0).toDouble() : null;

    final h = DateTime.now().hour;
    final greeting = h < 12 ? 'Good morning' : (h < 17 ? 'Good afternoon' : 'Good evening');

    return Container(
      width: double.infinity,
      color: M.heroBg,
      padding: const EdgeInsets.fromLTRB(20, 10, 18, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: () => context.push('/settings'),
                child: CircleAvatar(
                  radius: 20,
                  backgroundColor: M.heroAvatarBg,
                  backgroundImage: (user?.avatar != null && user!.avatar!.isNotEmpty)
                      ? NetworkImage(user.avatar!)
                      : null,
                  child: (user?.avatar == null || user!.avatar!.isEmpty)
                      ? Text(
                          (user?.name.isNotEmpty ?? false) ? user!.name[0].toUpperCase() : '?',
                          style: const TextStyle(fontWeight: FontWeight.w500, color: M.heroAvatarText, fontSize: 13),
                        )
                      : null,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(greeting, style: const TextStyle(color: M.heroMuted, fontSize: 12)),
                    Text(user?.name ?? '',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: Colors.white),
                        overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              _HeroIconButton(
                icon: Icons.notifications_none_rounded,
                showDot: true,
                onTap: () => context.push('/notifications'),
              ),
              const SizedBox(width: 10),
              _HeroIconButton(
                icon: Icons.grid_view_rounded,
                onTap: () => context.push('/quick-actions'),
              ),
            ],
          ),
          if (pct != null) ...[
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Sales target this month', style: TextStyle(fontSize: 11, color: M.heroMuted)),
                        const SizedBox(height: 2),
                        RichText(
                          text: TextSpan(
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w500, color: Colors.white),
                            children: [
                              TextSpan(text: '${pct.toStringAsFixed(0)}% '),
                              TextSpan(
                                text: 'of ₹${compact(target?['target'])}',
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: M.heroMuted),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 48,
                    height: 48,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        CircularProgressIndicator(
                          value: (pct / 100).clamp(0, 1),
                          strokeWidth: 5,
                          backgroundColor: Colors.white.withValues(alpha: 0.15),
                          valueColor: const AlwaysStoppedAnimation(M.heroRing),
                        ),
                        Text('${pct.toStringAsFixed(0)}%',
                            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HeroIconButton extends StatelessWidget {
  const _HeroIconButton({required this.icon, required this.onTap, this.showDot = false});
  final IconData icon;
  final VoidCallback onTap;
  final bool showDot;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.12), shape: BoxShape.circle),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(icon, size: 17, color: Colors.white),
            if (showDot)
              Positioned(
                top: 6,
                right: 6,
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(color: M.heroDot, shape: BoxShape.circle),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════ Personal stats (leads / follow-ups / streak / rank) ══════════════════════════

class _PersonalStatsStrip extends ConsumerWidget {
  const _PersonalStatsStrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(dashboardMeProvider);
    return async.maybeWhen(
      orElse: () => const SizedBox(height: 0),
      data: (d) {
        final leads = (d['leads'] is Map) ? (d['leads'] as Map) : const {};
        final followUps = (d['follow_ups'] is Map) ? (d['follow_ups'] as Map) : const {};
        final counts = (followUps['counts'] is Map) ? (followUps['counts'] as Map) : const {};
        final followUpTotal = (counts['missed'] ?? 0) + (counts['late'] ?? 0) + (counts['due_today'] ?? 0);
        final streak = (d['streak'] is Map) ? (d['streak'] as Map) : const {};
        final rank = (d['rank'] is Map) ? (d['rank'] as Map) : const {};
        final rankLabel = rank['position'] != null ? '#${rank['position']}' : '—';

        final chips = <(String, String, Tint)>[
          ('New leads', '${leads['new_today'] ?? 0}', tintPeach),
          ('Follow-ups', '$followUpTotal', tintBlue),
          ('Day streak', '${streak['days'] ?? 0}', tintAmber),
          ('Rank of ${rank['total_staff'] ?? 0}', rankLabel, tintLavender),
        ];

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Row(
            children: chips
                .map((c) => Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(right: c == chips.last ? 0 : 8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                          decoration: BoxDecoration(color: c.$3.$1, borderRadius: BorderRadius.circular(12)),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(c.$2, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w500, color: c.$3.$2)),
                              Text(c.$1,
                                  style: TextStyle(fontSize: 10, color: c.$3.$3),
                                  overflow: TextOverflow.ellipsis),
                            ],
                          ),
                        ),
                      ),
                    ))
                .toList(),
          ),
        );
      },
    );
  }
}

// ══════════════════════════ Company statistics (existing, permission-gated) ══════════════════════════

class _StatsStrip extends ConsumerWidget {
  const _StatsStrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Company-wide message/lead/contact/campaign totals — gated behind the
    // same permission as the dedicated Analytics module tile.
    if (!PermissionGuard.can('dashboard.view')) return const SizedBox(height: 0);

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
        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 6, 20, 0),
                child: SectionHeader('Statistics'),
              ),
              SizedBox(
                height: 66,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: chips.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (_, i) {
                    final theme = Theme.of(context);
                    return Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
              ),
            ],
          ),
        );
      },
    );
  }
}

// ══════════════════════════ Pipeline ══════════════════════════

class _PipelineSection extends ConsumerWidget {
  const _PipelineSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(dashboardMeProvider);
    return async.maybeWhen(
      orElse: () => const SizedBox(height: 0),
      data: (d) {
        final pipeline = (d['pipeline'] is Map) ? (d['pipeline'] as Map) : const {};
        final stages = <(String, int, Tint)>[
          ('New', (pipeline['new'] ?? 0) as int, tintPeach),
          ('Contacted', (pipeline['contacted'] ?? 0) as int, tintAmber),
          ('Won', (pipeline['won'] ?? 0) as int, tintGreen),
        ];
        if (stages.every((s) => s.$2 == 0)) return const SizedBox(height: 0);

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionHeader('Pipeline',
                  action: TextButton(
                      onPressed: () => context.push('/leads'),
                      child: const Text('View all'))),
              Row(
                children: stages
                    .map((s) => Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(right: s == stages.last ? 0 : 8),
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: s.$3.$1,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('${s.$2}',
                                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: s.$3.$2)),
                                  Text(s.$1, style: TextStyle(color: s.$3.$3, fontSize: 10)),
                                ],
                              ),
                            ),
                          ),
                        ))
                    .toList(),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ══════════════════════════ Follow-ups ══════════════════════════

const _followUpFilters = ['All', 'Missed', 'Late', 'Call', 'Message'];

class _FollowUpsSection extends ConsumerStatefulWidget {
  const _FollowUpsSection();
  @override
  ConsumerState<_FollowUpsSection> createState() => _FollowUpsSectionState();
}

class _FollowUpsSectionState extends ConsumerState<_FollowUpsSection> {
  String _filter = 'All';

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(dashboardMeProvider);
    return async.maybeWhen(
      orElse: () => const SizedBox(height: 0),
      data: (d) {
        final followUps = (d['follow_ups'] is Map) ? (d['follow_ups'] as Map) : const {};
        final counts = (followUps['counts'] is Map) ? (followUps['counts'] as Map) : const {};
        final items = (followUps['items'] is List)
            ? (followUps['items'] as List).whereType<Map>().toList()
            : const <Map>[];
        if (items.isEmpty) return const SizedBox(height: 0);

        final filtered = items.where((f) {
          switch (_filter) {
            case 'Missed':
              return f['bucket'] == 'missed';
            case 'Late':
              return f['bucket'] == 'late';
            case 'Call':
              return f['type'] == 'call';
            case 'Message':
              return f['type'] == 'whatsapp' || f['type'] == 'email';
            default:
              return true;
          }
        }).toList();

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionHeader('Follow-ups',
                  action: TextButton(
                      onPressed: () => context.push('/leads'),
                      child: const Text('View all'))),
              Row(
                children: [
                  Expanded(child: _CountTile(label: 'Missed', value: counts['missed'] ?? 0, tint: tintRed)),
                  const SizedBox(width: 8),
                  Expanded(child: _CountTile(label: 'Late', value: counts['late'] ?? 0, tint: tintAmber)),
                  const SizedBox(width: 8),
                  Expanded(child: _CountTile(label: 'Due today', value: counts['due_today'] ?? 0, tint: tintBlue)),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 32,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _followUpFilters.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 6),
                  itemBuilder: (_, i) {
                    final f = _followUpFilters[i];
                    final selected = f == _filter;
                    final theme = Theme.of(context);
                    return ChoiceChip(
                      label: Text(f),
                      selected: selected,
                      onSelected: (_) => setState(() => _filter = f),
                      labelStyle: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                          color: selected ? theme.colorScheme.surface : context.mutedColor),
                      selectedColor: theme.colorScheme.onSurface,
                      backgroundColor: context.altSurface,
                      side: BorderSide.none,
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              if (filtered.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text('Nothing in this filter.', style: TextStyle(color: context.mutedColor)),
                )
              else
                ...filtered.take(8).map((f) => _FollowUpRow(item: f.cast<String, dynamic>())),
            ],
          ),
        );
      },
    );
  }
}

class _CountTile extends StatelessWidget {
  const _CountTile({required this.label, required this.value, required this.tint});
  final String label;
  final Object? value;
  final Tint tint;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 8),
      decoration: BoxDecoration(color: tint.$1, borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          Text('${value ?? 0}', style: TextStyle(fontWeight: FontWeight.w500, fontSize: 17, color: tint.$2)),
          Text(label, style: TextStyle(color: tint.$3, fontSize: 10)),
        ],
      ),
    );
  }
}

class _FollowUpRow extends StatelessWidget {
  const _FollowUpRow({required this.item});
  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final type = str(item['type'], 'call');
    final bucket = str(item['bucket'], 'due_today');
    final icon = type == 'call' ? Icons.call_rounded : Icons.message_rounded;
    final (pillLabel, tint) = switch (bucket) {
      'missed' => ('Missed', tintRed),
      'late' => ('Late ${item['days_late'] ?? 1}d', tintAmber),
      _ => ('Due today', tintBlue),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: tint.$1, borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 16, color: tint.$2),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(str(item['contact_name'], item['title'] ?? 'Follow-up'),
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    overflow: TextOverflow.ellipsis),
                Text('${type == 'call' ? 'Call' : 'Message'} · ${_dueLabel(item['due_at'])}',
                    style: TextStyle(color: context.mutedColor, fontSize: 11.5)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: tint.$1, borderRadius: BorderRadius.circular(8)),
            child: Text(pillLabel, style: TextStyle(color: tint.$2, fontSize: 10, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  static String _dueLabel(Object? v) {
    final d = DateTime.tryParse('${v ?? ''}')?.toLocal();
    if (d == null) return '—';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final that = DateTime(d.year, d.month, d.day);
    final time = time12(d.toIso8601String());
    if (that == today) return 'due $time';
    if (that == today.subtract(const Duration(days: 1))) return 'due yesterday';
    if (that.isBefore(today)) return 'due ${today.difference(that).inDays}d ago';
    return 'scheduled $time';
  }
}

// ══════════════════════════ Team attendance (managers) ══════════════════════════

class _TeamAttendanceToday extends ConsumerWidget {
  const _TeamAttendanceToday();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(hrTeamAttendanceTodayProvider);
    return async.maybeWhen(
      orElse: () => const SizedBox(height: 0),
      data: (rows) {
        if (rows.isEmpty) return const SizedBox(height: 0);
        final shown = rows.take(6).toList();
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionHeader('Team attendance · today (${rows.length})'),
              ...shown.map((r) {
                final u = (r['user'] is Map) ? (r['user'] as Map) : const {};
                final status = str(r['status'], 'absent');
                final clockIn = r['clock_in_at'];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 16,
                        backgroundColor:
                            Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
                        child: Text(
                          str(u['name'], '?').substring(0, 1).toUpperCase(),
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: Theme.of(context).colorScheme.primary,
                              fontSize: 12.5),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(str(u['name'], 'Staff'),
                            style: const TextStyle(fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis),
                      ),
                      Text(
                        clockIn != null ? time12(clockIn) : '—',
                        style: TextStyle(color: context.mutedColor, fontSize: 12.5),
                      ),
                      const SizedBox(width: 10),
                      StatusPill(status),
                    ],
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }
}

// ══════════════════════════ Today's tasks ══════════════════════════

class _TodayTasks extends ConsumerWidget {
  const _TodayTasks();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(dashboardMeProvider);
    return async.maybeWhen(
      orElse: () => const SizedBox(height: 0),
      data: (d) {
        final tasks = (d['tasks'] is Map) ? (d['tasks'] as Map) : const {};
        final items = (tasks['items'] is List)
            ? (tasks['items'] as List).whereType<Map>().toList()
            : const <Map>[];
        if (items.isEmpty) return const SizedBox(height: 0);
        final done = tasks['done'] ?? 0;
        final total = tasks['total'] ?? items.length;

        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionHeader("Today's tasks", action: Text('$done of $total done', style: TextStyle(color: context.mutedColor, fontSize: 12))),
              ...items.take(8).map((t) {
                final isDone = str(t['status'], 'open') == 'done';
                final priority = str(t['priority'], '');
                final dotColor = priority == 'high' ? M.priorityHigh : M.priorityMed;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () async {
                        final ok = await runAction(
                            context, () => Api.post('/crm/tasks/${t['id']}/toggle'),
                            success: isDone ? null : 'Task completed');
                        if (ok) {
                          ref.invalidate(dashboardMeProvider);
                          ref.invalidate(crmMyTasksProvider);
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            isDone
                                ? Container(
                                    width: 18,
                                    height: 18,
                                    decoration: BoxDecoration(color: M.taskDoneBg, borderRadius: BorderRadius.circular(5)),
                                    child: const Icon(Icons.check_rounded, size: 13, color: Colors.white),
                                  )
                                : Container(
                                    width: 18,
                                    height: 18,
                                    decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(5),
                                        border: Border.all(color: context.lineColor, width: 1.5)),
                                  ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(str(t['title'], 'Task'),
                                  style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12.5,
                                      decoration: isDone ? TextDecoration.lineThrough : null,
                                      color: isDone ? context.mutedColor : null)),
                            ),
                            if (!isDone && priority.isNotEmpty && priority != '—')
                              Padding(
                                padding: const EdgeInsets.only(left: 8, top: 4),
                                child: Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }
}

// ══════════════════════════ Next up ══════════════════════════

class _NextUpCard extends ConsumerWidget {
  const _NextUpCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(dashboardMeProvider);
    return async.maybeWhen(
      orElse: () => const SizedBox(height: 0),
      data: (d) {
        final next = d['next_up'];
        if (next is! Map) return const SizedBox(height: 0);
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: M.lavenderBg, borderRadius: BorderRadius.circular(14)),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(color: M.lavenderIconBg, borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.event_repeat_rounded, size: 18, color: M.lavenderTitle),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Next up: ${str(next['subtitle'])}',
                          style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 12, color: M.lavenderTitle)),
                      Text(
                        '${str(next['title'])} · ${time12(next['at'])}',
                        style: const TextStyle(color: M.lavenderMuted, fontSize: 11),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
