import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:unichat_mobile_app/core/network/api.dart';
import 'package:unichat_mobile_app/core/theme/app_theme.dart';

final _msgTrendProvider = FutureProvider((ref) => Api.one('/analytics/messages'));
final _leadTrendProvider = FutureProvider((ref) => Api.one('/analytics/leads'));

/// One line (or two, for sent vs received) over [labels]; smooth, gradient-filled.
class TrendLineChart extends StatelessWidget {
  const TrendLineChart({
    super.key,
    required this.labels,
    required this.series,
    required this.colors,
    this.legend = const [],
  });
  final List<String> labels;
  final List<List<double>> series;
  final List<Color> colors;
  final List<String> legend;

  @override
  Widget build(BuildContext context) {
    final maxY = series.expand((s) => s).fold<double>(0, (a, b) => b > a ? b : a);
    if (labels.length < 2 || maxY == 0) {
      return SizedBox(
        height: 60,
        child: Center(
            child: Text('No trend data yet',
                style: TextStyle(color: context.mutedColor, fontSize: 12))),
      );
    }
    final step = (labels.length / 5).ceil();
    return Column(children: [
      SizedBox(
        height: 120,
        child: LineChart(LineChartData(
          minY: 0,
          maxY: maxY * 1.2,
          gridData: FlGridData(
            drawVerticalLine: false,
            horizontalInterval: maxY * 1.2 / 3,
            getDrawingHorizontalLine: (_) =>
                FlLine(color: context.lineColor, strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 30,
                interval: maxY * 1.2 / 3,
                getTitlesWidget: (v, _) => Text(
                  v >= 1000 ? '${(v / 1000).toStringAsFixed(1)}k' : v.toStringAsFixed(0),
                  style: TextStyle(color: context.mutedColor, fontSize: 9.5),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 20,
                interval: 1,
                getTitlesWidget: (v, _) {
                  final i = v.toInt();
                  if (i < 0 || i >= labels.length || i % step != 0) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(labels[i],
                        style: TextStyle(color: context.mutedColor, fontSize: 9.5)),
                  );
                },
              ),
            ),
          ),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (spots) => [
                for (final s in spots)
                  LineTooltipItem('${labels[s.x.toInt()]}  ${s.y.toInt()}',
                      TextStyle(color: s.bar.color, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          lineBarsData: [
            for (var k = 0; k < series.length; k++)
              LineChartBarData(
                spots: [for (var i = 0; i < series[k].length; i++) FlSpot(i.toDouble(), series[k][i])],
                isCurved: true,
                curveSmoothness: 0.25,
                barWidth: 2.6,
                color: colors[k],
                dotData: FlDotData(show: labels.length <= 8),
                belowBarData: BarAreaData(
                  show: true,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [colors[k].withOpacity(0.25), colors[k].withOpacity(0)],
                  ),
                ),
              ),
          ],
        )),
      ),
      if (legend.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var k = 0; k < legend.length; k++) ...[
              Container(width: 8, height: 8, decoration: BoxDecoration(color: colors[k], shape: BoxShape.circle)),
              const SizedBox(width: 5),
              Text(legend[k], style: TextStyle(color: context.mutedColor, fontSize: 11)),
              const SizedBox(width: 14),
            ],
          ]),
        ),
    ]);
  }
}

const _mon = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// Last 6 calendar months (oldest first) as "YYYY-MM" keys + short labels, so months with
/// no rows plot as 0 instead of being skipped.
(List<String>, List<String>) _last6Months() {
  final now = DateTime.now();
  final keys = <String>[], labels = <String>[];
  for (var i = 5; i >= 0; i--) {
    final d = DateTime(now.year, now.month - i, 1);
    keys.add('${d.year}-${d.month.toString().padLeft(2, '0')}');
    labels.add(_mon[d.month - 1]);
  }
  return (keys, labels);
}

List<double> _monthly(Object? rows, List<String> keys) {
  final by = <String, double>{};
  if (rows is List) {
    for (final r in rows.whereType<Map>()) {
      by['${r['month']}'] = (num.tryParse('${r['total']}') ?? 0).toDouble();
    }
  }
  return [for (final k in keys) by[k] ?? 0];
}

/// Chart for one Statistics group: 'WA Cloud' | 'CRM' | 'Leads'.
class StatsGroupChart extends ConsumerWidget {
  const StatsGroupChart({super.key, required this.group, required this.color, required this.overview});
  final String group;
  final Color color;
  final Map overview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Widget card(Widget child) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
          child: Container(
            padding: const EdgeInsets.fromLTRB(8, 12, 12, 8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: context.lineColor),
            ),
            child: child,
          ),
        );

    final (keys, labels) = _last6Months();
    switch (group) {
      case 'WA Cloud':
        final async = ref.watch(_msgTrendProvider);
        return async.maybeWhen(
          data: (d) {
            final daily = d['daily_30_days'];
            final days = <String>[];
            final out = <double>[], inn = <double>[];
            if (daily is Map) {
              final ks = daily.keys.map((e) => '$e').toList()..sort();
              for (final k in ks) {
                final v = daily[k];
                days.add(k.length >= 10 ? k.substring(8, 10) : k);
                out.add((num.tryParse('${v is Map ? v['outbound'] : 0}') ?? 0).toDouble());
                inn.add((num.tryParse('${v is Map ? v['inbound'] : 0}') ?? 0).toDouble());
              }
            }
            return card(TrendLineChart(
              labels: days,
              series: [out, inn],
              colors: [color, const Color(0xFFF59E0B)],
              legend: const ['Sent', 'Received'],
            ));
          },
          orElse: () => const SizedBox.shrink(),
        );
      case 'CRM':
        final c = overview['contacts'];
        return card(TrendLineChart(
          labels: labels,
          series: [_monthly(c is Map ? c['monthly'] : null, keys)],
          colors: [color],
          legend: const ['New contacts / month'],
        ));
      default:
        final async = ref.watch(_leadTrendProvider);
        return async.maybeWhen(
          data: (d) => card(TrendLineChart(
            labels: labels,
            series: [_monthly(d['monthly_new'], keys)],
            colors: [color],
            legend: const ['New leads / month'],
          )),
          orElse: () => const SizedBox.shrink(),
        );
    }
  }
}
