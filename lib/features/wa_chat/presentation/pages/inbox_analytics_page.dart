// ignore_for_file: use_build_context_synchronously
import "package:fl_chart/fl_chart.dart";
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:unichat_mobile_app/features/modules/module_providers.dart";
import "package:unichat_mobile_app/features/modules/_shared.dart";

// ══════════════════════════ Inbox Analytics ══════════════════════════
// Mirrors frontend/src/pages/wa-chat/pages/Analytics.tsx: company-wide message stats
// aggregated server-side (Laravel's /wa-chat/analytics fans out over each of this company's
// sessions with its own scoped gateway key — no gateway ADMIN role needed for this page).

const _connectedStatuses = {'ready', 'connected', 'working', 'authenticated'};

class InboxAnalyticsPage extends ConsumerWidget {
  const InboxAnalyticsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(waChatAnalyticsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Inbox Analytics')),
      body: AsyncView<Rec>(
        value: async,
        onRefresh: () async => ref.invalidate(waChatAnalyticsProvider),
        data: (d) {
          final overview = (d['overview'] is Map) ? d['overview'] as Map : const {};
          final bySession = (d['by_session'] is List) ? d['by_session'] as List : const [];
          final hourly = (d['hourly_activity'] is List) ? d['hourly_activity'] as List : const [];
          final topChats = (d['top_chats'] is List) ? d['top_chats'] as List : const [];

          return ListView(
            padding: const EdgeInsets.all(16),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
                Text(
                  "Aggregated across this company's ${overview['sessions_total'] ?? 0} session${(overview['sessions_total'] ?? 0) == 1 ? '' : 's'}.",
                  style: TextStyle(fontSize: 12, color: context.mutedColor),
                ),
                const SizedBox(height: 12),
                if (d['connected'] == false)
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(color: AppPalette.warning.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                    child: const Row(children: [
                      Icon(Icons.warning_amber_rounded, color: AppPalette.warning, size: 18),
                      SizedBox(width: 8),
                      Expanded(child: Text("The gateway didn't return stats for any session — figures below may be incomplete.")),
                    ]),
                  ),
                StatGrid([
                  ('Sessions', '${overview['sessions_total'] ?? 0}', Icons.smartphone_rounded),
                  ('Connected', '${overview['sessions_connected'] ?? 0}', Icons.wifi_rounded),
                  ('Sent (all time)', '${overview['messages_sent'] ?? 0}', Icons.send_rounded),
                  ('Received (all time)', '${overview['messages_received'] ?? 0}', Icons.inbox_rounded),
                  ('Today', '${overview['messages_today'] ?? 0}', Icons.today_rounded),
                  ('Failed', '${overview['messages_failed'] ?? 0}', Icons.error_outline_rounded),
                ]),
                const SizedBox(height: 24),
                if (hourly.isNotEmpty) _hourlyChart(context, hourly),
                if (bySession.isNotEmpty) ...[
                  const Text('By session', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  const SizedBox(height: 10),
                  ...bySession.map((s) {
                    final m = s as Map;
                    final status = str(m['status'], 'unknown');
                    return RecordCard(
                      title: str(m['name']),
                      subtitle: 'Sent ${m['sent'] ?? 0} · Received ${m['received'] ?? 0} · Today ${m['today'] ?? 0}'
                          '${(m['failed'] ?? 0) != 0 ? ' · Failed ${m['failed']}' : ''}'
                          '${m['reachable'] == false ? ' · unreachable' : ''}',
                      leadingIcon: Icons.smartphone_rounded,
                      leadingColor: _connectedStatuses.contains(status) ? AppPalette.success : null,
                      trailing: StatusPill(status),
                    );
                  }),
                  const SizedBox(height: 24),
                ],
                if (topChats.isNotEmpty) _topChatsChart(context, topChats),
              ],
            );
        },
      ),
    );
  }

  Widget _hourlyChart(BuildContext context, List hourly) {
    final maxY = hourly.fold<double>(1, (m, h) {
      final map = h as Map;
      final v = (num.tryParse('${map['sent'] ?? 0}') ?? 0) + (num.tryParse('${map['received'] ?? 0}') ?? 0);
      return v > m ? v.toDouble() : m;
    });
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Activity by hour of day', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 10),
          SizedBox(
            height: 200,
            child: BarChart(BarChartData(
              maxY: maxY * 1.15,
              gridData: const FlGridData(show: true, drawVerticalLine: false),
              borderData: FlBorderData(show: false),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipItem: (group, groupIdx, rod, rodIdx) {
                    final m = hourly[group.x.toInt()] as Map;
                    return BarTooltipItem(
                      '${str(m['hour'], '0').padLeft(2, '0')}:00\nSent ${m['sent'] ?? 0} · Recv ${m['received'] ?? 0}',
                      const TextStyle(color: Colors.white, fontSize: 11),
                    );
                  },
                ),
              ),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 30,
                    getTitlesWidget: (v, meta) => Text(v.toInt().toString(), style: TextStyle(fontSize: 10, color: context.mutedColor)))),
                bottomTitles: AxisTitles(sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 22,
                  interval: 3,
                  getTitlesWidget: (v, meta) {
                    final i = v.toInt();
                    if (i < 0 || i >= hourly.length) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(str((hourly[i] as Map)['hour'], '0').padLeft(2, '0'), style: TextStyle(fontSize: 9, color: context.mutedColor)),
                    );
                  },
                )),
              ),
              barGroups: [
                for (var i = 0; i < hourly.length; i++)
                  BarChartGroupData(x: i, barRods: [
                    BarChartRodData(
                      toY: (num.tryParse('${(hourly[i] as Map)['sent'] ?? 0}') ?? 0).toDouble() +
                          (num.tryParse('${(hourly[i] as Map)['received'] ?? 0}') ?? 0).toDouble(),
                      width: 8,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                      rodStackItems: [
                        BarChartRodStackItem(0, (num.tryParse('${(hourly[i] as Map)['received'] ?? 0}') ?? 0).toDouble(), const Color(0xFF93C5FD)),
                        BarChartRodStackItem(
                          (num.tryParse('${(hourly[i] as Map)['received'] ?? 0}') ?? 0).toDouble(),
                          (num.tryParse('${(hourly[i] as Map)['received'] ?? 0}') ?? 0).toDouble() + (num.tryParse('${(hourly[i] as Map)['sent'] ?? 0}') ?? 0).toDouble(),
                          const Color(0xFF6366F1),
                        ),
                      ],
                    ),
                  ]),
              ],
            )),
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 16, children: [
            _legendDot(context, const Color(0xFF6366F1), 'Sent'),
            _legendDot(context, const Color(0xFF93C5FD), 'Received'),
          ]),
        ],
      ),
    );
  }

  Widget _topChatsChart(BuildContext context, List topChats) {
    final chats = topChats.take(10).toList();
    final maxCount = chats.fold<num>(1, (m, c) {
      final v = num.tryParse('${(c as Map)['count'] ?? 0}') ?? 0;
      return v > m ? v : m;
    });
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Top chats', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 10),
          ...chats.map((c) {
            final m = c as Map;
            final name = str(m['chat_name'], '').isNotEmpty ? str(m['chat_name']) : str(m['chat_id'], '').split('@').first;
            final count = num.tryParse('${m['count'] ?? 0}') ?? 0;
            final frac = maxCount == 0 ? 0.0 : (count / maxCount).clamp(0.0, 1.0);
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                    const SizedBox(width: 8),
                    Text('$count msgs', style: TextStyle(fontSize: 11, color: context.mutedColor)),
                  ]),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: frac,
                      minHeight: 8,
                      backgroundColor: context.altSurface,
                      valueColor: const AlwaysStoppedAnimation(Color(0xFF6366F1)),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _legendDot(BuildContext context, Color color, String label) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 12, color: context.mutedColor)),
      ]);
}
