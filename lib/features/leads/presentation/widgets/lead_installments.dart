// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:unichat_mobile_app/features/modules/_shared.dart';

/// Bumped whenever a plan / payment changes anywhere, so every open Installments tab reloads.
final ValueNotifier<int> installmentsChanged = ValueNotifier<int>(0);

String _fmtDate(Object? iso) {
  final d = DateTime.tryParse('$iso');
  if (d == null) return '—';
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${d.day} ${m[d.month - 1]} ${d.year}';
}

String _iso(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
double _n(Object? v) => double.tryParse('${v ?? ''}') ?? 0;
DateTime _plusMonths(DateTime d, int n) => DateTime(d.year, d.month + n, d.day);

const _actionLabels = {
  'plan_created': 'Plan created', 'edited': 'Edited', 'paid': 'Payment', 'reversed': 'Payment reversed', 'waived': 'Waived',
  'followup': 'Follow-up', 'assigned': 'Follow-up person changed', 'late_fee': 'Late fee added', 'credit_kept': 'Earlier credit kept',
};

/// Set up a lead's instalment plan: total, how many, first due date, then each instalment's own date and amount (they may differ).
/// Returns true when a plan was saved.
Future<bool> showInstallmentPlanSetup(BuildContext context, int leadId, Object? saleValue) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _PlanSetup(leadId: leadId, saleValue: saleValue),
  );
  if (saved == true) installmentsChanged.value++;
  return saved == true;
}

class _PlanSetup extends StatefulWidget {
  const _PlanSetup({required this.leadId, required this.saleValue});
  final int leadId;
  final Object? saleValue;
  @override
  State<_PlanSetup> createState() => _PlanSetupState();
}

class _PlanSetupState extends State<_PlanSetup> {
  late final TextEditingController _total = TextEditingController(text: widget.saleValue == null ? '' : '${_n(widget.saleValue)}'.replaceAll(RegExp(r'\.0+$'), ''));
  final _count = TextEditingController(text: '3');
  DateTime _first = DateTime.now();
  final List<DateTime> _dates = [];
  final List<TextEditingController> _amts = [];
  bool _busy = false;

  @override
  void dispose() {
    _total.dispose();
    _count.dispose();
    for (final c in _amts) {
      c.dispose();
    }
    super.dispose();
  }

  void _split() {
    final n = (int.tryParse(_count.text) ?? 1).clamp(1, 60);
    final t = _n(_total.text);
    final base = (t / n * 100).floorToDouble() / 100;
    for (final c in _amts) {
      c.dispose();
    }
    _dates
      ..clear()
      ..addAll(List.generate(n, (i) => _plusMonths(_first, i)));
    _amts
      ..clear()
      ..addAll(List.generate(n, (i) => TextEditingController(text: (i == n - 1 ? ((t - base * (n - 1)) * 100).round() / 100 : base).toString().replaceAll(RegExp(r'\.0+$'), ''))));
    setState(() {});
  }

  double get _sum => _amts.fold(0.0, (a, c) => a + _n(c.text));
  bool get _ok => _amts.isNotEmpty && (_sum - _n(_total.text)).abs() < 0.01;

  Future<void> _save() async {
    setState(() => _busy = true);
    final ok = await runAction(
      context,
      () => Api.post('/leads/${widget.leadId}/installments/plan', data: {
        'total_amount': _n(_total.text),
        'installments': [for (var i = 0; i < _amts.length; i++) {'due_date': _iso(_dates[i]), 'amount': _n(_amts[i].text)}],
      }),
      success: 'Installment plan saved',
    );
    if (mounted) setState(() => _busy = false);
    if (ok && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Set up installments', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('The lead keeps its full value; the plan says how it is collected. Amounts can differ, but must add up to the total.', style: TextStyle(fontSize: 12, color: context.mutedColor)),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(child: TextField(controller: _total, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Total (₹)', border: OutlineInputBorder(), isDense: true), onChanged: (_) => setState(() {}))),
              const SizedBox(width: 10),
              Expanded(child: TextField(controller: _count, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'No. of installments', border: OutlineInputBorder(), isDense: true))),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.event_rounded, size: 18),
                  label: Text('First due: ${_fmtDate(_iso(_first))}'),
                  onPressed: () async {
                    final p = await showDatePicker(context: context, initialDate: _first, firstDate: DateTime.now().subtract(const Duration(days: 365)), lastDate: DateTime.now().add(const Duration(days: 1500)));
                    if (p != null) setState(() => _first = p);
                  },
                ),
              ),
              const SizedBox(width: 10),
              FilledButton.tonal(onPressed: _n(_total.text) > 0 ? _split : null, child: const Text('Split evenly')),
            ]),
            if (_amts.isNotEmpty) ...[
              const SizedBox(height: 12),
              for (var i = 0; i < _amts.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(children: [
                    SizedBox(width: 24, child: Text('${i + 1}', style: const TextStyle(fontWeight: FontWeight.w700))),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          final p = await showDatePicker(context: context, initialDate: _dates[i], firstDate: DateTime.now().subtract(const Duration(days: 365)), lastDate: DateTime.now().add(const Duration(days: 1500)));
                          if (p != null) setState(() => _dates[i] = p);
                        },
                        child: Text(_fmtDate(_iso(_dates[i]))),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(width: 110, child: TextField(controller: _amts[i], keyboardType: TextInputType.number, decoration: const InputDecoration(prefixText: '₹', border: OutlineInputBorder(), isDense: true), onChanged: (_) => setState(() {}))),
                  ]),
                ),
              Text('Adds up to ${money(_sum)} of ${money(_n(_total.text))}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _ok ? Colors.green.shade700 : Colors.red.shade600)),
            ],
            const SizedBox(height: 14),
            Row(children: [
              Expanded(child: OutlinedButton(onPressed: _busy ? null : () => Navigator.pop(context, false), child: const Text('Cancel'))),
              const SizedBox(width: 10),
              Expanded(child: FilledButton(onPressed: _busy || !_ok ? null : _save, child: Text(_busy ? 'Saving…' : 'Save plan'))),
            ]),
          ],
        ),
      ),
    );
  }
}

/// The lead's Installments tab: the plan, record payments / follow-ups, and (HR) edit, waive, reverse. Every action is in the log below.
class LeadInstallmentsTab extends StatefulWidget {
  const LeadInstallmentsTab({super.key, required this.leadId, this.saleValue});
  final int leadId;
  final Object? saleValue;
  @override
  State<LeadInstallmentsTab> createState() => _LeadInstallmentsTabState();
}

class _LeadInstallmentsTabState extends State<LeadInstallmentsTab> {
  Rec? _d;
  String? _error;
  bool _showLog = false;

  @override
  void initState() {
    super.initState();
    installmentsChanged.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    installmentsChanged.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await Api.one('/leads/${widget.leadId}/installments');
      if (mounted) setState(() { _d = r; _error = null; });
    } catch (e) {
      if (mounted) setState(() => _error = apiErrorMessage(e));
    }
  }

  Future<void> _act(Future<Rec> Function() call, String ok) async {
    final done = await runAction(context, () async { await call(); }, success: ok);
    if (done) installmentsChanged.value++;
  }

  Future<String?> _ask(String title, {String hint = 'Reason'}) {
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(title),
          content: TextField(controller: c, autofocus: true, maxLines: 2, decoration: InputDecoration(hintText: hint), onChanged: (_) => set(() {})),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            TextButton(onPressed: c.text.trim().isEmpty ? null : () => Navigator.pop(ctx, c.text.trim()), child: const Text('Continue')),
          ],
        ),
      ),
    );
  }

  Future<void> _pay(Rec i) async {
    final amount = TextEditingController(text: '${_n(i['balance'])}'.replaceAll(RegExp(r'\.0+$'), ''));
    final fee = TextEditingController(text: _n(i['fee_due']) > 0 ? '${_n(i['fee_due'])}' : '');
    final method = TextEditingController();
    final ref = TextEditingController();
    var paidOn = DateTime.now();
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text('Record payment — #${i['seq']}'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: amount, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'Amount received (balance ${money(i['balance'])})')),
              if (_n(i['fee_due']) > 0) TextField(controller: fee, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'Late fee collected (due ${money(i['fee_due'])})')),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.event_rounded, size: 18),
                label: Text('Paid on ${_fmtDate(_iso(paidOn))}'),
                onPressed: () async {
                  final p = await showDatePicker(context: ctx, initialDate: paidOn, firstDate: DateTime.now().subtract(const Duration(days: 365)), lastDate: DateTime.now());
                  if (p != null) set(() => paidOn = p);
                },
              ),
              TextField(controller: method, decoration: const InputDecoration(labelText: 'Method (UPI, cash…)')),
              TextField(controller: ref, decoration: const InputDecoration(labelText: 'Reference / receipt no.')),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (go != true) return;
    await _act(
      () => Api.post('/installments/${i['id']}/pay', data: {
        'amount': _n(amount.text), 'late_fee_amount': _n(fee.text), 'paid_on': _iso(paidOn),
        if (method.text.trim().isNotEmpty) 'method': method.text.trim(), if (ref.text.trim().isNotEmpty) 'reference': ref.text.trim(),
      }),
      'Payment recorded',
    );
  }

  Future<void> _followup(Rec i) async {
    final note = TextEditingController();
    DateTime? promised = DateTime.tryParse('${i['promised_on'] ?? ''}');
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text('Follow-up — #${i['seq']}'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: note, maxLines: 2, decoration: const InputDecoration(labelText: 'What happened?', hintText: 'Called, will pay on Friday…')),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.event_rounded, size: 18),
              label: Text(promised == null ? 'Promised to pay on…' : 'Promised ${_fmtDate(_iso(promised!))}'),
              onPressed: () async {
                final p = await showDatePicker(context: ctx, initialDate: promised ?? DateTime.now(), firstDate: DateTime.now().subtract(const Duration(days: 30)), lastDate: DateTime.now().add(const Duration(days: 730)));
                if (p != null) set(() => promised = p);
              },
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (go != true) return;
    await _act(() => Api.post('/installments/${i['id']}/followup', data: {if (note.text.trim().isNotEmpty) 'note': note.text.trim(), if (promised != null) 'promised_on': _iso(promised!)}), 'Follow-up saved');
  }

  Future<void> _edit(Rec i) async {
    final amount = TextEditingController(text: '${_n(i['amount'])}'.replaceAll(RegExp(r'\.0+$'), ''));
    var due = DateTime.tryParse('${i['due_date']}') ?? DateTime.now();
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text('Edit installment #${i['seq']}'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.event_rounded, size: 18),
              label: Text('Due ${_fmtDate(_iso(due))}'),
              onPressed: () async {
                final p = await showDatePicker(context: ctx, initialDate: due, firstDate: DateTime.now().subtract(const Duration(days: 365)), lastDate: DateTime.now().add(const Duration(days: 1500)));
                if (p != null) set(() => due = p);
              },
            ),
            TextField(controller: amount, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Amount (₹)')),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (go != true) return;
    await _act(() => Api.patch('/installments/${i['id']}', data: {'due_date': _iso(due), 'amount': _n(amount.text)}), 'Saved');
  }

  Color _statusColor(Rec i) {
    if (i['overdue'] == true) return Colors.red.shade600;
    return switch ('${i['status']}') { 'paid' => Colors.green.shade700, 'partial' => Colors.orange.shade800, 'waived' => Colors.grey, _ => Colors.blue.shade700 };
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!)));
    final d = _d;
    if (d == null) return const Center(child: CircularProgressIndicator());
    final plan = d['plan'] is Map ? (d['plan'] as Map).cast<String, dynamic>() : null;
    final isHr = d['is_hr'] == true;
    final canFollow = d['can_follow_up'] == true;
    final inst = ((d['installments'] as List?) ?? const []).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
    final payments = ((d['payments'] as List?) ?? const []).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
    final log = ((d['log'] as List?) ?? const []).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (plan == null) ...[
            const SizedBox(height: 24),
            const Icon(Icons.payments_outlined, size: 48, color: Colors.grey),
            const SizedBox(height: 10),
            const Center(child: Text('No installment plan', style: TextStyle(fontWeight: FontWeight.w700))),
            const SizedBox(height: 4),
            Center(child: Text('Is the student paying in parts? Set up when each installment is due and how much.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: context.mutedColor))),
            const SizedBox(height: 16),
            Center(child: FilledButton.icon(icon: const Icon(Icons.add_rounded), label: const Text('Set up installments'), onPressed: () => showInstallmentPlanSetup(context, widget.leadId, d['sale_value'] ?? widget.saleValue))),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(14)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: _stat('Total', money(plan['total_amount']))),
                  Expanded(child: _stat('Collected', money(plan['collected']), color: Colors.green.shade700)),
                  Expanded(child: _stat('Balance', money(plan['balance']), color: Colors.red.shade600)),
                ]),
                const SizedBox(height: 10),
                ClipRRect(borderRadius: BorderRadius.circular(6), child: LinearProgressIndicator(minHeight: 8, value: _n(plan['total_amount']) > 0 ? (_n(plan['collected']) / _n(plan['total_amount'])).clamp(0, 1) : 0)),
              ]),
            ),
            if (plan['credit_mode'] == 'upfront')
              Container(
                margin: const EdgeInsets.only(top: 10),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.amber.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
                child: const Text('This sale was already credited in full, and its incentive paid out, before the plan was made. That credit stays, so these payments are not counted toward target or incentive again.', style: TextStyle(fontSize: 11.5)),
              ),
            const SizedBox(height: 12),
            for (final i in inst)
              Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Text('#${i['seq']}', style: const TextStyle(fontWeight: FontWeight.w800)),
                      const SizedBox(width: 8),
                      Expanded(child: Text('Due ${_fmtDate(i['due_date'])}${i['overdue'] == true ? ' · ${i['days_overdue']}d late' : ''}', style: TextStyle(fontSize: 12.5, color: i['overdue'] == true ? Colors.red.shade600 : null))),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: _statusColor(i).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                        child: Text(i['overdue'] == true ? 'overdue' : '${i['status']}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _statusColor(i))),
                      ),
                    ]),
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(child: _stat('Amount', money(i['amount']))),
                      Expanded(child: _stat('Paid', money(i['paid']), color: Colors.green.shade700)),
                      Expanded(child: _stat('Balance', money(i['balance']))),
                    ]),
                    if (_n(i['late_fee']) > 0) Padding(padding: const EdgeInsets.only(top: 4), child: Text('+${money(i['late_fee'])} late fee${_n(i['fee_due']) > 0 ? ' (${money(i['fee_due'])} due)' : ' (paid)'}', style: TextStyle(fontSize: 11.5, color: Colors.red.shade600))),
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('Follow-up by ${str(i['assigned_name'], 'lead owner')}${i['promised_on'] != null && i['status'] != 'paid' ? ' · promised ${_fmtDate(i['promised_on'])}' : ''}', style: TextStyle(fontSize: 11.5, color: context.mutedColor)),
                    ),
                    if (i['status'] != 'paid' && i['status'] != 'waived')
                      Wrap(spacing: 6, children: [
                        if (canFollow) TextButton(onPressed: () => _pay(i), child: const Text('Record payment')),
                        if (canFollow) TextButton(onPressed: () => _followup(i), child: const Text('Follow-up')),
                        if (isHr) TextButton(onPressed: () => _edit(i), child: const Text('Edit')),
                        if (isHr)
                          TextButton(
                            onPressed: () async {
                              final r = await _ask('Reason for waiving #${i['seq']}?');
                              if (r != null) await _act(() => Api.post('/installments/${i['id']}/waive', data: {'reason': r}), 'Waived');
                            },
                            child: Text('Waive', style: TextStyle(color: Colors.red.shade600)),
                          ),
                      ]),
                  ]),
                ),
              ),
            if (payments.isNotEmpty) ...[
              const SizedBox(height: 6),
              const Text('Payments', style: TextStyle(fontWeight: FontWeight.w700)),
              for (final p in payments)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text('${money(p['amount'])}${_n(p['late_fee_amount']) > 0 ? ' + ${money(p['late_fee_amount'])} fee' : ''}', style: TextStyle(decoration: p['reversed_at'] != null ? TextDecoration.lineThrough : null)),
                  subtitle: Text('${_fmtDate(p['paid_on'])}${p['method'] != null ? ' · ${p['method']}' : ''}${p['reference'] != null ? ' · ${p['reference']}' : ''}${p['recorded_name'] != null ? ' · ${p['recorded_name']}' : ''}'),
                  trailing: isHr && p['reversed_at'] == null
                      ? TextButton(
                          onPressed: () async {
                            final r = await _ask('Reason for reversing this payment?\nIts target credit and pending incentive are taken back.');
                            if (r != null) await _act(() => Api.post('/installments/payments/${p['id']}/reverse', data: {'reason': r}), 'Payment reversed');
                          },
                          child: Text('Reverse', style: TextStyle(color: Colors.red.shade600)),
                        )
                      : null,
                ),
            ],
            const SizedBox(height: 6),
            TextButton(onPressed: () => setState(() => _showLog = !_showLog), child: Text('${_showLog ? 'Hide' : 'Show'} activity log (${log.length})')),
            if (_showLog)
              for (final l in log)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    '${when(l['created_at'])} · ${_actionLabels[l['action']] ?? l['action']}${l['by'] != null ? ' by ${l['by']}' : ''}'
                    '${(l['details_arr'] is Map && (l['details_arr']['note'] ?? l['details_arr']['reason']) != null) ? ' — ${l['details_arr']['note'] ?? l['details_arr']['reason']}' : ''}',
                    style: TextStyle(fontSize: 11.5, color: context.mutedColor),
                  ),
                ),
          ],
        ],
      ),
    );
  }

  Widget _stat(String label, String value, {Color? color}) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 10.5, color: context.mutedColor)),
          Text(value, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: color)),
        ],
      );
}
