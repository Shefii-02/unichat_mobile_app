import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:unichat_mobile_app/core/network/api.dart';
import 'package:unichat_mobile_app/core/theme/app_theme.dart';

/// One dashboard per section — Tasks, Meta Ads, Instagram, Messenger, AI Agent. The server (SectionDashboardController) decides the
/// content and answers every section in the same shape, so this single page serves all five.
final sectionDashProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, ({String endpoint, String channel})>(
    (ref, k) => Api.one(k.endpoint, query: k.channel.isEmpty ? null : {'channel': k.channel}),
    // Riverpod 3 re-tries a failed provider many times and shows the spinner meanwhile — a failed dashboard must say so at once instead
    // (pull down to try again).
    retry: (count, error) => null);

/// 12345678 -> "1,23,45,678" (Indian digit grouping, as the web uses).
String groupIndian(String whole) {
  if (whole.length <= 3) return whole;
  final last3 = whole.substring(whole.length - 3);
  var rest = whole.substring(0, whole.length - 3);
  final parts = <String>[];
  while (rest.length > 2) {
    parts.insert(0, rest.substring(rest.length - 2));
    rest = rest.substring(0, rest.length - 2);
  }
  if (rest.isNotEmpty) parts.insert(0, rest);
  return '${parts.join(',')},$last3';
}

/// "₹1,700" / "1.14%" / "12,345" for a headline number.
String formatKpi(Map k) {
  final raw = k['value'];
  final n = raw is num ? raw : num.tryParse('$raw');
  if (n == null) return '$raw';
  String grouped(num v, {int decimals = 0}) {
    final s = v.toStringAsFixed(v == v.roundToDouble() ? 0 : decimals);
    final parts = s.split('.');
    return parts.length > 1 ? '${groupIndian(parts[0])}.${parts[1]}' : groupIndian(parts[0]);
  }

  return switch (k['format']) {
    'money' => '₹${grouped(n, decimals: 2)}',
    'percent' => '$n%',
    _ => grouped(n),
  };
}

class SectionDashboardPage extends ConsumerWidget {
  const SectionDashboardPage({super.key, required this.title, required this.endpoint, this.channel = ''});
  final String title, endpoint, channel;

  static const _tone = {'green': Color(0xFF16A34A), 'red': Color(0xFFDC2626), 'amber': Color(0xFFD97706)};

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (endpoint: endpoint, channel: channel);
    final async = ref.watch(sectionDashProvider(key));
    return Scaffold(
      appBar: AppBar(title: Text('$title Dashboard')),
      body: RefreshIndicator(
        onRefresh: () async => ref.refresh(sectionDashProvider(key).future),
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(children: [
            Padding(
              padding: const EdgeInsets.all(32),
              child: Text('Could not load the dashboard. Pull down to try again.',
                  key: const ValueKey('dash-error'), textAlign: TextAlign.center, style: TextStyle(color: context.mutedColor)),
            ),
          ]),
          data: (d) => _body(context, d),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, Map<String, dynamic> d) {
    final kpis = (d['kpis'] is List ? d['kpis'] as List : const []).whereType<Map>().toList();
    final lists = (d['lists'] is List ? d['lists'] as List : const []).whereType<Map>().toList();
    final series = d['series'] is Map ? d['series'] as Map : const {};
    final lines = (series['lines'] is List ? series['lines'] as List : const []).whereType<Map>().toList();
    final width = (MediaQuery.of(context).size.width - 16 * 2 - 10) / 2;
    return ListView(
      padding: const EdgeInsets.all(16),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        Text('${d['title'] ?? ''}', style: TextStyle(color: context.mutedColor, fontSize: 12.5)),
        const SizedBox(height: 12),
        Wrap(spacing: 10, runSpacing: 10, children: [
          for (final k in kpis)
            Container(
              key: ValueKey('kpi-${k['label']}'),
              width: width,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: context.lineColor),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${k['label']}'.toUpperCase(),
                    maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: context.mutedColor, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.3)),
                const SizedBox(height: 4),
                Text(formatKpi(k),
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: _tone['${k['tone']}'])),
              ]),
            ),
        ]),
        if (lines.isNotEmpty) ...[
          const SizedBox(height: 18),
          Text('${series['title'] ?? ''} · last ${d['range_days'] ?? 30} days', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          const SizedBox(height: 10),
          SizedBox(key: const ValueKey('dash-chart'), height: 180, child: _chart(lines)),
          const SizedBox(height: 6),
          Wrap(spacing: 14, children: [
            for (final l in lines)
              Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 10, height: 10, decoration: BoxDecoration(color: _color(l['color']), shape: BoxShape.circle)),
                const SizedBox(width: 5),
                Text('${l['label']}', style: const TextStyle(fontSize: 11.5)),
              ]),
          ]),
        ],
        for (final l in lists) _list(context, l),
        const SizedBox(height: 24),
      ],
    );
  }

  static Color _color(Object? hex) {
    final h = '$hex'.replaceFirst('#', '');
    final v = int.tryParse(h.length == 6 ? 'FF$h' : h, radix: 16);
    return Color(v ?? 0xFF6366F1);
  }

  Widget _chart(List<Map> lines) {
    return LineChart(LineChartData(
      gridData: const FlGridData(drawVerticalLine: false),
      borderData: FlBorderData(show: false),
      titlesData: const FlTitlesData(
        topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 36)),
      ),
      lineBarsData: [
        for (final l in lines)
          LineChartBarData(
            isCurved: true,
            color: _color(l['color']),
            barWidth: 2.5,
            dotData: const FlDotData(show: false),
            spots: [
              for (final e in (l['points'] as List).whereType<Map>().toList().asMap().entries)
                FlSpot(e.key.toDouble(), ((e.value['value'] ?? 0) as num).toDouble()),
            ],
          ),
      ],
    ));
  }

  Widget _list(BuildContext context, Map l) {
    final cols = (l['columns'] as List).map((c) => '$c').toList();
    final rows = (l['rows'] as List).whereType<List>().toList();
    return Container(
      key: ValueKey('dash-list-${l['title']}'),
      margin: const EdgeInsets.only(top: 18),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.lineColor),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${l['title']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        const SizedBox(height: 8),
        if (rows.isEmpty)
          Text('Nothing here yet.', style: TextStyle(color: context.mutedColor, fontSize: 12))
        else ...[
          Row(children: [
            for (var i = 0; i < cols.length; i++)
              Expanded(
                flex: i == 0 ? 3 : 2,
                child: Text(cols[i], textAlign: i == 0 ? TextAlign.start : TextAlign.end,
                    style: TextStyle(color: context.mutedColor, fontSize: 10.5, fontWeight: FontWeight.w700)),
              ),
          ]),
          const Divider(height: 14),
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                for (var i = 0; i < r.length; i++)
                  Expanded(
                    flex: i == 0 ? 3 : 2,
                    child: Text('${r[i]}', maxLines: 2, overflow: TextOverflow.ellipsis,
                        textAlign: i == 0 ? TextAlign.start : TextAlign.end,
                        style: TextStyle(fontSize: 12.5, fontWeight: i == 0 ? FontWeight.w600 : FontWeight.w400)),
                  ),
              ]),
            ),
        ],
      ]),
    );
  }
}
