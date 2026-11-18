import 'package:dio/dio.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:unichat_mobile_app/core/network/api.dart';
import 'package:unichat_mobile_app/core/theme/app_theme.dart';
import 'package:unichat_mobile_app/core/widgets/data_widgets.dart';
import 'package:unichat_mobile_app/features/modules/_shared.dart';

/// Company-admin Home block: WA Cloud plan usage (templates, campaigns, this month's
/// campaigns vs their limits) and a filterable multi-series chart
/// (GET /analytics/wa-cloud-home?range=…).
/// Key is "<endpoint>|<range>", e.g. "wa-cloud-home|this_month".
final _waCloudHomeProvider = FutureProvider.family<Map<String, dynamic>, String>((ref, key) {
  final p = key.split('|');
  return Api.one('/analytics/${p[0]}', query: {'range': p[1]});
});

const _ranges = [
  ('today', 'Today'),
  ('last_week', 'Last week'),
  ('this_month', 'This month'),
  ('last_month', 'Last month'),
  ('last_3_months', 'Last 3 months'),
];

class _Metric {
  const _Metric(this.key, this.label, this.color);
  final String key, label;
  final Color color;
}

/// WA Cloud chart metrics.
const waCloudMetrics = [
  _Metric('incoming', 'Incoming msgs', Color(0xFF0EA5E9)),
  _Metric('outgoing', 'Sent msgs', Color(0xFF22C55E)),
  _Metric('campaigns', 'Campaigns', Color(0xFFF97316)),
];

/// Leads chart metrics (GET /analytics/leads-home).
const leadsMetrics = [
  _Metric('leads', 'Leads', Color(0xFF7C3AED)),
  _Metric('converted', 'Converted', Color(0xFF16A34A)),
  _Metric('closed', 'Closed', Color(0xFF0D9488)),
  _Metric('rejected', 'Rejected', Color(0xFFDC2626)),
  _Metric('pending', 'Pending', Color(0xFFF59E0B)),
  _Metric('followups', 'Follow-ups', Color(0xFF0EA5E9)),
];

num _n(Object? v) => v is num ? v : (num.tryParse('${v ?? ''}') ?? 0);

class WaCloudHome extends ConsumerStatefulWidget {
  /// [chartOnly] renders just the filter + multi-bar chart (used under the usage cards in
  /// Statistics → WA Cloud); otherwise header + usage cards + chart (company-admin Home).
  const WaCloudHome({
    super.key,
    this.chartOnly = false,
    this.endpoint = 'wa-cloud-home',
    this.metrics = waCloudMetrics,
  });
  final bool chartOnly;
  final String endpoint;
  final List<_Metric> metrics;
  @override
  ConsumerState<WaCloudHome> createState() => _WaCloudHomeState();
}

class _WaCloudHomeState extends ConsumerState<WaCloudHome> {
  String _range = 'this_month';
  bool _bars = true;
  String _metric = 'all';

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(_waCloudHomeProvider('${widget.endpoint}|$_range'));
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!widget.chartOnly) Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(children: [
              const Icon(Icons.cloud_rounded, size: 18, color: Color(0xFF0EA5E9)),
              const SizedBox(width: 6),
              Expanded(child: SectionHeader('WA Cloud overview')),
            ]),
          ),
          async.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(30),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            ),
            error: (e, _) => Container(
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFDC2626).withOpacity(0.08),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(children: [
                const Icon(Icons.cloud_off_rounded, color: Color(0xFFDC2626)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                      "Couldn't load ${widget.endpoint == 'leads-home' ? 'leads chart' : 'WA Cloud overview'} — "
                      "${e is DioException && e.response?.statusCode == 404 ? 'server update pending (route not found)' : apiErrorMessage(e)}",
                      style: const TextStyle(fontSize: 12.5)),
                ),
                TextButton(
                  onPressed: () => ref.invalidate(_waCloudHomeProvider('${widget.endpoint}|$_range')),
                  child: const Text('Retry'),
                ),
              ]),
            ),
            data: (d) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!widget.chartOnly) ...[_usageRow(context, d), const SizedBox(height: 14)],
                _chartCard(context, theme, d),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Usage: templates / campaigns / this month ──
  Widget _usageRow(BuildContext context, Map<String, dynamic> d) {
    Map m(String k) => d[k] is Map ? d[k] as Map : const {};
    final t = m('templates'), c = m('campaigns'), cm = m('campaigns_month');
    return Column(children: [
      Row(children: [
        Expanded(child: _UsageCard(
          title: 'Templates', icon: Icons.description_rounded,
          color: const Color(0xFF0EA5E9), used: _n(t['used']), limit: t['limit'])),
        const SizedBox(width: 10),
        Expanded(child: _UsageCard(
          title: 'Total campaigns', icon: Icons.campaign_rounded,
          color: const Color(0xFFF97316), used: _n(c['used']), limit: c['limit'])),
      ]),
      const SizedBox(height: 10),
      _MonthCard(
        running: _n(cm['running']).toInt(),
        completed: _n(cm['completed']).toInt(),
        used: _n(cm['used']),
        limit: cm['limit'],
      ),
    ]);
  }

  // ── Filters + chart ──
  Widget _chartCard(BuildContext context, ThemeData theme, Map<String, dynamic> d) {
    final series = (d['series'] is List ? d['series'] as List : const []).whereType<Map>().toList();
    final totals = d['totals'] is Map ? d['totals'] as Map : const {};
    final active = _metric == 'all' ? widget.metrics : widget.metrics.where((m) => m.key == _metric).toList();

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.lineColor),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Range · metric · chart type — one inline row of dropdowns.
        Row(children: [
          Expanded(
            flex: 5,
            child: _Drop<String>(
              value: _range,
              items: [for (final r in _ranges) DropdownMenuItem(value: r.$1, child: Text(r.$2, overflow: TextOverflow.ellipsis))],
              onChanged: (v) => setState(() => _range = v ?? _range),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            flex: 4,
            child: _Drop<String>(
              value: _metric,
              items: [
                const DropdownMenuItem(value: 'all', child: Text('All')),
                for (final m in widget.metrics)
                  DropdownMenuItem(value: m.key, child: Text(m.label, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) => setState(() => _metric = v ?? 'all'),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            flex: 2,
            child: _Drop<bool>(
              value: _bars,
              items: const [
                DropdownMenuItem(value: true, child: Icon(Icons.bar_chart_rounded, size: 20)),
                DropdownMenuItem(value: false, child: Icon(Icons.show_chart_rounded, size: 20)),
              ],
              onChanged: (v) => setState(() => _bars = v ?? true),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 14, runSpacing: 6, children: [
          for (final m in active)
            Row(mainAxisSize: MainAxisSize.min, children: [
              CircleAvatar(radius: 4, backgroundColor: m.color),
              const SizedBox(width: 5),
              Text('${m.label}  ',
                  style: TextStyle(color: context.mutedColor, fontSize: 11.5)),
              Text(compact(totals[m.key]),
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
            ]),
        ]),
        const SizedBox(height: 14),
        _MultiChart(rows: series, metrics: active, bars: _bars),
      ]),
    );
  }
}

/// The three plan-usage cards on their own (templates / total campaigns / this month),
/// every "limit" being the company's plan maximum (incl. purchased add-ons). Used by the
/// Statistics → WA Cloud group.
/// Compact pill dropdown used for the chart's inline filter row.
class _Drop<T> extends StatelessWidget {
  const _Drop({required this.value, required this.items, required this.onChanged});
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: context.lineColor.withOpacity(0.35),
        borderRadius: BorderRadius.circular(12),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          isDense: true,
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
          style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurface),
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class WaCloudUsageCards extends ConsumerWidget {
  const WaCloudUsageCards({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_waCloudHomeProvider('wa-cloud-home|this_month'));
    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(20),
        child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Text("Couldn't load — ${apiErrorMessage(e)}",
            style: TextStyle(color: context.mutedColor, fontSize: 12)),
      ),
      data: (d) {
        Map m(String k) => d[k] is Map ? d[k] as Map : const {};
        final t = m('templates'), c = m('campaigns'), cm = m('campaigns_month');
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(children: [
            Row(children: [
              Expanded(child: _UsageCard(title: 'Templates', icon: Icons.description_rounded,
                  color: const Color(0xFF0EA5E9), used: _n(t['used']), limit: t['limit'])),
              const SizedBox(width: 10),
              Expanded(child: _UsageCard(title: 'Total campaigns', icon: Icons.campaign_rounded,
                  color: const Color(0xFFF97316), used: _n(c['used']), limit: c['limit'])),
            ]),
            const SizedBox(height: 10),
            _MonthCard(
              running: _n(cm['running']).toInt(),
              completed: _n(cm['completed']).toInt(),
              used: _n(cm['used']),
              limit: cm['limit'],
            ),
          ]),
        );
      },
    );
  }
}

class _UsageCard extends StatelessWidget {
  const _UsageCard({required this.title, required this.icon, required this.color, required this.used, required this.limit});
  final String title;
  final IconData icon;
  final Color color;
  final num used;
  final Object? limit;

  @override
  Widget build(BuildContext context) {
    final lim = limit == null ? null : _n(limit);
    final pct = lim == null ? 0.0 : (lim == 0 ? 1.0 : (used / lim).clamp(0, 1).toDouble());
    final bar = pct >= 1 ? const Color(0xFFDC2626) : color;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color.withOpacity(0.16), color.withOpacity(0.05)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withOpacity(0.28)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(color: color.withOpacity(0.18), borderRadius: BorderRadius.circular(9)),
            child: Icon(icon, size: 17, color: color),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(title, style: TextStyle(color: context.mutedColor, fontSize: 12, fontWeight: FontWeight.w700))),
        ]),
        const SizedBox(height: 12),
        RichText(
          text: TextSpan(
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            children: [
              TextSpan(text: compact(used)),
              TextSpan(
                text: ' / ${lim == null ? '∞' : compact(lim)}',
                style: TextStyle(color: context.mutedColor, fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            value: lim == null ? 0 : pct,
            minHeight: 6,
            backgroundColor: color.withOpacity(0.15),
            color: bar,
          ),
        ),
      ]),
    );
  }
}

class _MonthCard extends StatelessWidget {
  const _MonthCard({required this.running, required this.completed, required this.used, required this.limit});
  final int running, completed;
  final num used;
  final Object? limit;

  @override
  Widget build(BuildContext context) {
    final lim = limit == null ? null : _n(limit);
    const runC = Color(0xFF0EA5E9), doneC = Color(0xFF16A34A), limC = Color(0xFFF97316);
    Widget cell(String label, String value, IconData icon, Color c) => Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(color: c.withOpacity(0.10), borderRadius: BorderRadius.circular(14)),
            child: Column(children: [
              Icon(icon, size: 18, color: c),
              const SizedBox(height: 6),
              FittedBox(
                child: Text(value, style: TextStyle(color: c, fontSize: 19, fontWeight: FontWeight.w800)),
              ),
              Text(label, style: TextStyle(color: context.mutedColor, fontSize: 11.5)),
            ]),
          ),
        );
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 14, 10, 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.lineColor),
      ),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
          child: Row(children: [
            const Icon(Icons.calendar_month_rounded, size: 16, color: limC),
            const SizedBox(width: 6),
            Text('Campaigns · this month',
                style: TextStyle(color: context.mutedColor, fontSize: 12, fontWeight: FontWeight.w700)),
          ]),
        ),
        Row(children: [
          cell('Running', '$running', Icons.play_circle_rounded, runC),
          cell('Completed', '$completed', Icons.check_circle_rounded, doneC),
          cell('Limit', lim == null ? '∞' : '${compact(used)}/${compact(lim)}', Icons.speed_rounded, limC),
        ]),
      ]),
    );
  }
}

/// Multi-series chart over the daily rows. Line mode plots every day; bar mode sums the
/// days into ≤12 buckets so a 3-month range stays readable.
class _MultiChart extends StatelessWidget {
  const _MultiChart({required this.rows, required this.metrics, required this.bars});
  final List<Map> rows;
  final List<_Metric> metrics;
  final bool bars;

  @override
  Widget build(BuildContext context) {
    final size = bars ? (rows.length / 12).ceil().clamp(1, 31) : 1;
    final buckets = <List<Map>>[];
    for (var i = 0; i < rows.length; i += size) {
      buckets.add(rows.sublist(i, (i + size).clamp(0, rows.length)));
    }
    double val(List<Map> b, String k) => b.fold<double>(0, (a, r) => a + _n(r[k]).toDouble());
    final data = {for (final m in metrics) m.key: [for (final b in buckets) val(b, m.key)]};
    final maxY = data.values.expand((e) => e).fold<double>(0, (a, b) => b > a ? b : a);

    if (buckets.isEmpty || (!bars && buckets.length < 2) || maxY == 0) {
      return SizedBox(
        height: 90,
        child: Center(child: Text('No activity in this period', style: TextStyle(color: context.mutedColor, fontSize: 12))),
      );
    }

    String label(int i) {
      final d = '${buckets[i].first['date']}';
      if (d.length > 10) return '${d.substring(11, 13)}h'; // hourly rows ("Today")
      return d.length >= 10 ? '${d.substring(8, 10)}/${d.substring(5, 7)}' : d;
    }

    final step = (buckets.length / 5).ceil();
    final interval = maxY * 1.2 / 3;
    final titles = FlTitlesData(
      topTitles: const AxisTitles(),
      rightTitles: const AxisTitles(),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 32,
          interval: interval,
          getTitlesWidget: (v, _) => Text(compact(v),
              style: TextStyle(color: context.mutedColor, fontSize: 9.5)),
        ),
      ),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 20,
          interval: 1,
          getTitlesWidget: (v, _) {
            final i = v.toInt();
            if (i < 0 || i >= buckets.length || i % step != 0) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(label(i), style: TextStyle(color: context.mutedColor, fontSize: 9.5)),
            );
          },
        ),
      ),
    );
    final grid = FlGridData(
      drawVerticalLine: false,
      horizontalInterval: interval,
      getDrawingHorizontalLine: (_) => FlLine(color: context.lineColor, strokeWidth: 1),
    );

    return SizedBox(
      height: 190,
      child: bars
          ? BarChart(BarChartData(
              maxY: maxY * 1.2,
              gridData: grid,
              borderData: FlBorderData(show: false),
              titlesData: titles,
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipItem: (g, _, rod, i) => BarTooltipItem(
                    '${metrics[i].label}  ${rod.toY.toInt()}',
                    TextStyle(color: rod.color, fontWeight: FontWeight.w700, fontSize: 11),
                  ),
                ),
              ),
              barGroups: [
                for (var i = 0; i < buckets.length; i++)
                  BarChartGroupData(
                    x: i,
                    barsSpace: 2,
                    barRods: [
                      for (final m in metrics)
                        BarChartRodData(
                          toY: data[m.key]![i],
                          color: m.color,
                          width: (10 / metrics.length).clamp(3, 8).toDouble(),
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                        ),
                    ],
                  ),
              ],
            ))
          : LineChart(LineChartData(
              minY: 0,
              maxY: maxY * 1.2,
              gridData: grid,
              borderData: FlBorderData(show: false),
              titlesData: titles,
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipItems: (spots) => [
                    for (final s in spots)
                      LineTooltipItem(
                        '${metrics[s.barIndex].label}  ${s.y.toInt()}',
                        TextStyle(color: s.bar.color, fontWeight: FontWeight.w700, fontSize: 11),
                      ),
                  ],
                ),
              ),
              lineBarsData: [
                for (final m in metrics)
                  LineChartBarData(
                    spots: [for (var i = 0; i < buckets.length; i++) FlSpot(i.toDouble(), data[m.key]![i])],
                    isCurved: true,
                    curveSmoothness: 0.2,
                    barWidth: 2.4,
                    color: m.color,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: metrics.length == 1,
                      color: m.color.withOpacity(0.12),
                    ),
                  ),
              ],
            )),
    );
  }
}


// ───────────────────── Campaign-wise: sent vs incoming responses ─────────────────────

final _campaignsHomeProvider = FutureProvider.family<Map<String, dynamic>, String>(
    (ref, range) => Api.one('/analytics/campaigns-home', query: {'range': range}));

class CampaignResponsesChart extends ConsumerStatefulWidget {
  const CampaignResponsesChart({super.key});
  @override
  ConsumerState<CampaignResponsesChart> createState() => _CampaignResponsesChartState();
}

class _CampaignResponsesChartState extends ConsumerState<CampaignResponsesChart> {
  String _range = 'this_month';
  static const _sentC = Color(0xFF0EA5E9), _respC = Color(0xFF22C55E);

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(_campaignsHomeProvider(_range));
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: context.lineColor),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.campaign_rounded, size: 18, color: Color(0xFFF97316)),
            const SizedBox(width: 6),
            const Expanded(
              child: Text('Campaign responses',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
            ),
            SizedBox(
              width: 130,
              child: _Drop<String>(
                value: _range,
                items: [for (final r in _ranges) DropdownMenuItem(value: r.$1, child: Text(r.$2, overflow: TextOverflow.ellipsis))],
                onChanged: (v) => setState(() => _range = v ?? _range),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          async.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
            ),
            error: (e, _) => Text("Couldn't load campaigns — ${apiErrorMessage(e)}",
                style: TextStyle(color: context.mutedColor, fontSize: 12)),
            data: (d) {
              final list = (d['campaigns'] is List ? d['campaigns'] as List : const []).whereType<Map>().toList();
              final totals = d['totals'] is Map ? d['totals'] as Map : const {};
              if (list.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  child: Center(child: Text('No campaigns in this period',
                      style: TextStyle(color: context.mutedColor, fontSize: 12.5))),
                );
              }
              final maxY = list.fold<double>(0, (a, c) {
                final m = _n(c['sent']) > _n(c['responses']) ? _n(c['sent']) : _n(c['responses']);
                return m > a ? m.toDouble() : a;
              });
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Wrap(spacing: 14, children: [
                  _legend('Messages sent', compact(totals['sent']), _sentC),
                  _legend('Incoming responses', compact(totals['responses']), _respC),
                ]),
                const SizedBox(height: 14),
                SizedBox(
                  height: 170,
                  child: BarChart(BarChartData(
                    maxY: (maxY == 0 ? 1 : maxY) * 1.2,
                    borderData: FlBorderData(show: false),
                    gridData: FlGridData(
                      drawVerticalLine: false,
                      getDrawingHorizontalLine: (_) => FlLine(color: context.lineColor, strokeWidth: 1),
                    ),
                    titlesData: FlTitlesData(
                      topTitles: const AxisTitles(),
                      rightTitles: const AxisTitles(),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 32,
                          getTitlesWidget: (v, meta) => v == meta.max
                              ? const SizedBox.shrink()
                              : Text(compact(v), style: TextStyle(color: context.mutedColor, fontSize: 9.5)),
                        ),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 22,
                          getTitlesWidget: (v, _) {
                            final i = v.toInt();
                            if (i < 0 || i >= list.length) return const SizedBox.shrink();
                            final n = '${list[i]['name'] ?? ''}';
                            return Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(n.length > 7 ? '${n.substring(0, 6)}…' : n,
                                  style: TextStyle(color: context.mutedColor, fontSize: 9.5)),
                            );
                          },
                        ),
                      ),
                    ),
                    barTouchData: BarTouchData(
                      touchTooltipData: BarTouchTooltipData(
                        getTooltipItem: (g, gi, rod, ri) => BarTooltipItem(
                          '${list[gi]['name']}\n${ri == 0 ? 'Sent' : 'Responses'}  ${rod.toY.toInt()}',
                          TextStyle(color: rod.color, fontWeight: FontWeight.w700, fontSize: 11),
                        ),
                      ),
                    ),
                    barGroups: [
                      for (var i = 0; i < list.length; i++)
                        BarChartGroupData(x: i, barsSpace: 3, barRods: [
                          BarChartRodData(
                              toY: _n(list[i]['sent']).toDouble(), color: _sentC, width: 8,
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(3))),
                          BarChartRodData(
                              toY: _n(list[i]['responses']).toDouble(), color: _respC, width: 8,
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(3))),
                        ]),
                    ],
                  )),
                ),
                const SizedBox(height: 12),
                for (final c in list)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(children: [
                      Expanded(
                        child: Text('${c['name'] ?? 'Campaign'}',
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
                      ),
                      Text('${compact(c['sent'])} sent',
                          style: const TextStyle(color: _sentC, fontSize: 12, fontWeight: FontWeight.w700)),
                      const SizedBox(width: 10),
                      Text('${compact(c['responses'])} replies',
                          style: const TextStyle(color: _respC, fontSize: 12, fontWeight: FontWeight.w700)),
                      const SizedBox(width: 8),
                      Text('${_n(c['response_rate'])}%',
                          style: TextStyle(color: context.mutedColor, fontSize: 11.5)),
                    ]),
                  ),
              ]);
            },
          ),
        ]),
      ),
    );
  }

  Widget _legend(String label, String value, Color c) => Row(mainAxisSize: MainAxisSize.min, children: [
        CircleAvatar(radius: 4, backgroundColor: c),
        const SizedBox(width: 5),
        Text('$label  ', style: TextStyle(color: context.mutedColor, fontSize: 11.5)),
        Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
      ]);
}
