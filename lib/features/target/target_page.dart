import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:unichat_mobile_app/core/theme/mockup_palette.dart';
import 'package:unichat_mobile_app/features/modules/_shared.dart';
import 'package:unichat_mobile_app/features/modules/module_providers.dart';

const _monthNames = [
  '', 'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

/// Sales target screen: this month's big progress ring, remaining amount + days left,
/// a weekly breakdown and team standing — all from `GET /hr/sales/me`
/// (see SalesController@me).
class TargetPage extends ConsumerWidget {
  const TargetPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(salesMeProvider(null));

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async => ref.invalidate(salesMeProvider),
          child: async.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => ListView(children: [
              const SizedBox(height: 140),
              Center(child: Text('$e', style: TextStyle(color: context.mutedColor))),
            ]),
            data: (d) {
              final progress = d['progress'];
              final pct = progress != null ? (num.tryParse('$progress') ?? 0).toDouble() : null;
              final month = DateTime.tryParse('${d['month']}-01') ?? DateTime.now();
              final weekly = (d['weekly'] is List) ? (d['weekly'] as List).whereType<Map>().toList() : const <Map>[];
              final leaderboard =
                  (d['leaderboard'] is List) ? (d['leaderboard'] as List).whereType<Map>().toList() : const <Map>[];

              return ListView(
                padding: const EdgeInsets.only(bottom: 32),
                children: [
                  Container(
                    width: double.infinity,
                    color: M.heroBg,
                    padding: const EdgeInsets.fromLTRB(20, 10, 18, 22),
                    child: Column(
                      children: [
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Text('Target',
                              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Colors.white)),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: 120,
                          height: 120,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              CircularProgressIndicator(
                                value: pct != null ? (pct / 100).clamp(0, 1) : 0,
                                strokeWidth: 10,
                                backgroundColor: Colors.white.withValues(alpha: 0.15),
                                valueColor: const AlwaysStoppedAnimation(M.heroRing),
                              ),
                              Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(pct != null ? '${pct.toStringAsFixed(0)}%' : '—',
                                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: Colors.white)),
                                  const Text('achieved', style: TextStyle(fontSize: 10, color: M.heroMuted)),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text('₹${compact(d['achieved'])} of ₹${compact(d['target'])} · ${_monthNames[month.month]}',
                            style: const TextStyle(fontSize: 13, color: M.heroMuted)),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: _MetricTile(
                            value: '₹${compact(d['remaining'])}',
                            label: 'Remaining',
                            tint: tintGreen,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _MetricTile(
                            value: '${d['days_left'] ?? 0} days',
                            label: 'Left this month',
                            tint: tintLavender,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (weekly.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SectionHeader('Weekly breakdown'),
                          ...weekly.map((w) {
                            final p = w['percent'];
                            final wp = p != null ? (num.tryParse('$p') ?? 0).toDouble() : null;
                            final fillColor = wp == null ? null : (wp >= 80 ? M.taskDoneBg : M.priorityMed);
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 44,
                                    child: Text(str(w['label']), style: TextStyle(fontSize: 11, color: context.mutedColor)),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(6),
                                      child: LinearProgressIndicator(
                                        value: wp != null ? (wp / 100).clamp(0, 1) : 0,
                                        minHeight: 8,
                                        backgroundColor: context.altSurface,
                                        valueColor: AlwaysStoppedAnimation(fillColor ?? Colors.transparent),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  SizedBox(
                                    width: 38,
                                    child: Text(
                                      wp != null ? '${wp.toStringAsFixed(0)}%' : '–',
                                      textAlign: TextAlign.right,
                                      style: TextStyle(fontSize: 11, color: wp == null ? context.mutedColor : null),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  if (leaderboard.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SectionHeader('Team standing'),
                          ...leaderboard.take(6).map((r) => _TeamRow(row: r.cast<String, dynamic>())),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.value, required this.label, required this.tint});
  final String value;
  final String label;
  final Tint tint;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(color: tint.$1, borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: tint.$2)),
          Text(label, style: TextStyle(fontSize: 10, color: tint.$3)),
        ],
      ),
    );
  }
}

const _avatarPalette = <(Color, Color)>[
  (M.lavenderIconBg, M.lavenderTitle),
  (Color(0xFFF0997B), M.peachTitle),
  (Color(0xFFB5D4F4), M.blueTitle),
  (M.gold, M.goldTitle),
  (Color(0xFF97C459), Color(0xFF173404)),
];

class _TeamRow extends StatelessWidget {
  const _TeamRow({required this.row});
  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final isMe = row['is_me'] == true;
    final rank = row['rank'] ?? 0;
    final name = str(row['name'], 'Staff');
    final initials = name.trim().isEmpty
        ? '?'
        : name.trim().split(' ').where((w) => w.isNotEmpty).map((w) => w[0].toUpperCase()).take(2).join();
    final palette = _avatarPalette[(rank is int ? rank : 1) % _avatarPalette.length];
    final percent = row['percent'];
    final pct = percent != null ? (num.tryParse('$percent') ?? 0).toDouble() : 0.0;

    return Container(
      padding: EdgeInsets.symmetric(vertical: 7, horizontal: isMe ? 8 : 0),
      margin: EdgeInsets.symmetric(horizontal: isMe ? -8 : 0),
      decoration: isMe ? BoxDecoration(color: context.altSurface, borderRadius: BorderRadius.circular(8)) : null,
      child: Row(
        children: [
          SizedBox(width: 18, child: Text('$rank', style: TextStyle(fontSize: 11, color: context.mutedColor))),
          const SizedBox(width: 8),
          CircleAvatar(
            radius: 13,
            backgroundColor: palette.$1,
            child: Text(initials, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: palette.$2)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(isMe ? '$name (you)' : name,
                style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis),
          ),
          Text('${pct.toStringAsFixed(0)}%', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
