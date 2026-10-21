import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:unichat_mobile_app/features/modules/_shared.dart';
import 'books_common.dart';

class BooksDashboardTab extends StatefulWidget {
  const BooksDashboardTab({super.key});
  @override
  State<BooksDashboardTab> createState() => _BooksDashboardTabState();
}

class _BooksDashboardTabState extends State<BooksDashboardTab> with AutomaticKeepAliveClientMixin {
  DateTimeRange _range = currentFy();
  Map<String, dynamic>? _d;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _d = null; _error = null; });
    try {
      final d = await getJson('/accounts/dashboard', query: {'from': isoDate(_range.start), 'to': isoDate(_range.end)});
      if (mounted) setState(() => _d = d);
    } catch (e) {
      if (mounted) setState(() => _error = apiErrorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final d = _d;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.all(12), children: [
        RangeBar(range: _range, onChanged: (r) { _range = r; _load(); }),
        const SizedBox(height: 8),
        if (_error != null) Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)),
        if (d == null && _error == null) const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())),
        if (d != null) ..._content(d),
      ]),
    );
  }

  List<Widget> _content(Map<String, dynamic> d) {
    final profit = numOf(d['profit']);
    final gst = (d['gst'] as Map?) ?? const {};
    final tiles = [
      StatTile(label: 'Income', value: inr(d['income']), icon: Icons.savings_rounded, tint: AppPalette.success),
      StatTile(label: 'Expenses', value: inr(d['expense']), icon: Icons.payments_rounded, tint: AppPalette.danger),
      StatTile(label: profit >= 0 ? 'Net profit' : 'Net loss', value: inr(profit.abs()), icon: Icons.trending_up_rounded, tint: profit >= 0 ? AppPalette.success : AppPalette.danger),
      StatTile(label: 'GST payable', value: inr(gst['total_payable']), icon: Icons.account_balance_rounded),
      StatTile(label: 'Cash in hand', value: inr(d['cash']), icon: Icons.money_rounded),
      StatTile(label: 'Bank balance', value: inr(d['bank']), icon: Icons.account_balance_wallet_rounded),
      StatTile(label: 'To receive', value: inr(d['receivable']), icon: Icons.call_received_rounded, tint: AppPalette.info),
      StatTile(label: 'To pay', value: inr(d['payable']), icon: Icons.call_made_rounded, tint: AppPalette.warning),
    ];
    final chart = asRecs(d['chart']);
    final top = asRecs(d['top_expenses']);
    return [
      GridView.count(
        crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: 1.7, children: tiles,
      ),
      const SectionHeader('Income vs expense'),
      if (chart.isEmpty)
        Padding(padding: const EdgeInsets.all(16), child: Text('No transactions in this period.', style: TextStyle(color: context.mutedColor)))
      else
        SizedBox(
          height: 220,
          child: BarChart(BarChartData(
            gridData: const FlGridData(show: true, drawVerticalLine: false),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(), rightTitles: const AxisTitles(),
              leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 44, getTitlesWidget: (v, _) => Text(compact(v), style: const TextStyle(fontSize: 10)))),
              bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: (v, _) {
                final i = v.toInt();
                return i >= 0 && i < chart.length ? Text('${chart[i]['month']}'.substring(2), style: const TextStyle(fontSize: 10)) : const SizedBox();
              })),
            ),
            barGroups: [
              for (var i = 0; i < chart.length; i++)
                BarChartGroupData(x: i, barRods: [
                  BarChartRodData(toY: numOf(chart[i]['income']).toDouble(), color: AppPalette.success, width: 8),
                  BarChartRodData(toY: numOf(chart[i]['expense']).toDouble(), color: AppPalette.danger, width: 8),
                ]),
            ],
          )),
        ),
      const SectionHeader('Top expenses'),
      if (top.isEmpty) Text('No expenses yet.', style: TextStyle(color: context.mutedColor)),
      for (final e in top) AmountRow('${e['name']}', e['amount']),
    ];
  }
}
