import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:unichat_mobile_app/core/theme/mockup_palette.dart';
import 'package:unichat_mobile_app/features/modules/_shared.dart';
import 'package:unichat_mobile_app/features/modules/module_providers.dart';

/// Self-service payroll screen: latest released payslip (net pay, earnings, deductions,
/// any one-off adjustments) plus past payslip history — from `GET /hr/payroll/me` and
/// `/hr/payroll/me/history` (see PayrollController@me / @meHistory). Draft (unreleased)
/// runs are never shown here — only what HR has finalised.
class PayrollPage extends ConsumerStatefulWidget {
  const PayrollPage({super.key});

  @override
  ConsumerState<PayrollPage> createState() => _PayrollPageState();
}

class _PayrollPageState extends ConsumerState<PayrollPage> {
  final _scrollCtrl = ScrollController();

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _scrollToHistory() {
    _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 400), curve: Curves.easeOut);
  }

  void _sharePayslip(Map<String, dynamic> s) {
    final period = _periodLabel(s['run']?['period']);
    final adjustments =
        (s['adjustments'] is List) ? (s['adjustments'] as List).whereType<Map>().toList() : const <Map>[];
    final lines = [
      'Payslip — $period',
      '',
      'Net pay: ₹${money(s['net_pay'])}',
      'Gross pay: ₹${money(s['gross_pay'])}',
      '',
      'Earnings',
      '  Base pay: ₹${money(s['base_pay'])}',
      '  Overtime pay: ₹${money(s['overtime_pay'])}',
      '  Allowances: ₹${money(s['allowances'])}',
      '  Sales incentive: ₹${money(s['incentive_pay'])}',
      '',
      'Deductions',
      '  Total deductions: ₹${money(s['deductions'])}',
      for (final a in adjustments) '  ${str(a['label'], 'Adjustment')}: ₹${money(a['amount'])}',
    ];
    Share.share(lines.join('\n'), subject: 'Payslip — $period');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final slipAsync = ref.watch(payrollMeProvider(null));
    final historyAsync = ref.watch(payrollHistoryProvider);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(payrollMeProvider);
            ref.invalidate(payrollHistoryProvider);
          },
          child: ListView(
            controller: _scrollCtrl,
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              Container(
                width: double.infinity,
                color: M.heroBg,
                padding: const EdgeInsets.fromLTRB(20, 10, 18, 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Payroll',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Colors.white)),
                    slipAsync.maybeWhen(
                      data: (s) => s == null
                          ? const SizedBox.shrink()
                          : Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                              decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(20)),
                              child: Text(_periodLabel(s['run']?['period']),
                                  style: const TextStyle(fontSize: 12, color: Colors.white)),
                            ),
                      orElse: () => const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
              slipAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.only(top: 60),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('$e', style: TextStyle(color: context.mutedColor)),
                ),
                data: (s) {
                  if (s == null) {
                    return Padding(
                      padding: const EdgeInsets.all(32),
                      child: Center(
                        child: Text('No released payslip yet.', style: TextStyle(color: context.mutedColor)),
                      ),
                    );
                  }
                  final adjustments =
                      (s['adjustments'] is List) ? (s['adjustments'] as List).whereType<Map>().toList() : const <Map>[];

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(color: M.pinkBg, borderRadius: BorderRadius.circular(14)),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Net pay', style: TextStyle(fontSize: 11, color: M.pinkMuted)),
                              Padding(
                                padding: const EdgeInsets.only(top: 2, bottom: 10),
                                child: Text('₹${money(s['net_pay'])}',
                                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600, color: M.pinkTitle)),
                              ),
                              Row(
                                children: [
                                  _NetPaySub(label: 'Gross', value: '₹${compact(s['gross_pay'])}'),
                                  const SizedBox(width: 18),
                                  _NetPaySub(label: 'Deductions', value: '₹${compact(s['deductions'])}'),
                                  const SizedBox(width: 18),
                                  _NetPaySub(label: 'Incentive', value: '₹${compact(s['incentive_pay'])}'),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SectionHeader('Earnings'),
                            _LineRow('Base pay', s['base_pay']),
                            _LineRow('Overtime pay', s['overtime_pay']),
                            _LineRow('Allowances', s['allowances']),
                            _LineRow('Sales incentive', s['incentive_pay']),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SectionHeader('Deductions'),
                            _LineRow('Total deductions', s['deductions']),
                            ...adjustments.map((a) => _LineRow(str(a['label'], 'Adjustment'), a['amount'])),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                        child: Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: _scrollToHistory,
                                child: const Text('Payslip history'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: FilledButton.icon(
                                style: FilledButton.styleFrom(backgroundColor: M.pinkSolid),
                                onPressed: () => _sharePayslip(s),
                                icon: const Icon(Icons.ios_share_rounded, size: 16),
                                label: const Text('Share'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
              historyAsync.maybeWhen(
                orElse: () => const SizedBox.shrink(),
                data: (rows) {
                  if (rows.isEmpty) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SectionHeader('Past payslips'),
                        ...rows.map((r) {
                          final run = (r['run'] is Map) ? (r['run'] as Map) : const {};
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              children: [
                                Icon(Icons.receipt_long_rounded, size: 17, color: context.mutedColor),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(_periodLabel(run['period']), style: const TextStyle(fontSize: 12.5)),
                                ),
                                Text('₹${money(r['net_pay'])}',
                                    style: TextStyle(fontSize: 12, color: context.mutedColor)),
                              ],
                            ),
                          );
                        }),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  static String _periodLabel(Object? period) {
    final d = DateTime.tryParse('${period ?? ''}-01');
    if (d == null) return str(period);
    const names = [
      '', 'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    return '${names[d.month]} ${d.year}';
  }
}

class _NetPaySub extends StatelessWidget {
  const _NetPaySub({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: M.pinkMuted)),
        Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: M.pinkTitle)),
      ],
    );
  }
}

class _LineRow extends StatelessWidget {
  const _LineRow(this.label, this.value);
  final String label;
  final Object? value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 12.5, color: context.mutedColor)),
          Text('₹${money(value)}', style: const TextStyle(fontSize: 12.5)),
        ],
      ),
    );
  }
}
