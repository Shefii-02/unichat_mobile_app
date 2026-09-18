// ignore_for_file: use_build_context_synchronously
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:unichat_mobile_app/features/modules/module_providers.dart";
import "package:unichat_mobile_app/features/modules/_shared.dart";

// ══════════════════════════ Payroll ══════════════════════════

/// Split out of the former shared `HrAdminPage` (tab 2, "Payroll").
class HrPayrollsPage extends ConsumerWidget {
  const HrPayrollsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Payrolls')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _generatePayrollRun(context),
        icon: const Icon(Icons.receipt_long_rounded),
        label: const Text('Generate run'),
      ),
      body: ProviderList(
      provider: hrPayrollRunsProvider,
      emptyLabel: 'No payroll runs yet',
      emptyIcon: Icons.receipt_long_rounded,
      tile: (context, r) {
        final totals = (r['totals'] is Map) ? (r['totals'] as Map) : const {};
        return RecordCard(
          title: str(r['period'], 'Run'),
          subtitle: '${r['items_count'] ?? totals['staff'] ?? 0} staff · net ${money(totals['net_pay'])}',
          leadingIcon: Icons.receipt_long_rounded,
          trailing: StatusPill(str(r['status'], 'draft')),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => _PayrollRunDetailPage(runId: r['id'] as int)),
          ),
        );
      },
      ),
    );
  }
}

Future<void> _generatePayrollRun(BuildContext context) async {
  final now = DateTime.now();
  final data = <String, dynamic>{'period': '${now.year}-${now.month.toString().padLeft(2, '0')}'};
  final ok = await showFormSheet(
    context,
    title: 'Generate payroll run',
    submitLabel: 'Generate',
    fields: (ctx) => [
      FText(
        label: 'Period (YYYY-MM)',
        initial: data['period'] as String,
        required: true,
        onSaved: (v) => data['period'] = v,
      ),
    ],
    onSubmit: () => Api.post('/hr/payroll/runs', data: data),
  );
  if (ok && context.mounted) {
    final container = ProviderScope.containerOf(context, listen: false);
    container.invalidate(hrPayrollRunsProvider);
  }
}

class _PayrollRunDetailPage extends StatefulWidget {
  const _PayrollRunDetailPage({required this.runId});
  final int runId;
  @override
  State<_PayrollRunDetailPage> createState() => _PayrollRunDetailPageState();
}

class _PayrollRunDetailPageState extends State<_PayrollRunDetailPage> {
  Rec? _run;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await Api.one('/hr/payroll/runs/${widget.runId}');
      setState(() { _run = res; _loading = false; });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _release() async {
    final ok = await confirm(context, title: 'Release this run?',
        message: 'Staff will be able to see their payslip once released. This cannot be undone.',
        confirmLabel: 'Release');
    if (!ok) return;
    final done = await runAction(context, () => Api.post('/hr/payroll/runs/${widget.runId}/release'), success: 'Released');
    if (done) _load();
  }

  @override
  Widget build(BuildContext context) {
    final run = _run;
    final released = str(run?['status']) == 'released';
    return Scaffold(
      appBar: AppBar(
        title: Text(str(run?['period'], 'Payroll run')),
        actions: [
          if (run != null && !released)
            TextButton(onPressed: _release, child: const Text('Release', style: TextStyle(color: Colors.white))),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : run == null
              ? Center(child: Text('Not found', style: TextStyle(color: context.mutedColor)))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      StatusPill(str(run['status'], 'draft')),
                      const SizedBox(height: 12),
                      ...((run['items'] is List) ? (run['items'] as List).whereType<Map>() : const <Map>[])
                          .map((raw) => raw.cast<String, dynamic>()).map((item) {
                        final user = (item['user'] is Map) ? (item['user'] as Map) : const {};
                        return RecordCard(
                          title: str(user['name'], 'Staff'),
                          subtitle: 'Gross ${money(item['gross_pay'])} · Net ${money(item['net_pay'])}',
                          leadingIcon: Icons.person_rounded,
                          trailing: released
                              ? null
                              : IconButton(
                                  icon: const Icon(Icons.edit_rounded, size: 18),
                                  onPressed: () => _editItem(item),
                                ),
                        );
                      }),
                    ],
                  ),
                ),
    );
  }

  Future<void> _editItem(Rec item) async {
    final data = <String, dynamic>{};
    final ok = await showFormSheet(
      context,
      title: 'Edit pay line',
      fields: (ctx) => [
        FNumber(label: 'Base pay', initial: item['base_pay'] as num?, onSaved: (v) => data['base_pay'] = v),
        FNumber(label: 'Overtime pay', initial: item['overtime_pay'] as num?, onSaved: (v) => data['overtime_pay'] = v),
        FNumber(label: 'Incentive pay', initial: item['incentive_pay'] as num?, onSaved: (v) => data['incentive_pay'] = v),
        FNumber(label: 'Allowances', initial: item['allowances'] as num?, onSaved: (v) => data['allowances'] = v),
        FNumber(label: 'Deductions', initial: item['deductions'] as num?, onSaved: (v) => data['deductions'] = v),
      ],
      onSubmit: () => Api.patch('/hr/payroll/items/${item['id']}', data: data),
    );
    if (ok) _load();
  }
}

// ══════════════════════════ Sales ══════════════════════════

