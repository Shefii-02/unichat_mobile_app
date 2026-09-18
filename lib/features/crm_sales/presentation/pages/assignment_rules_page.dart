// ignore_for_file: use_build_context_synchronously
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:go_router/go_router.dart";
import "package:unichat_mobile_app/features/modules/module_providers.dart";
import "package:unichat_mobile_app/features/modules/_shared.dart";
import "package:unichat_mobile_app/features/leads/lead_stage.dart";

// ══════════════════════════ Assignment Rules ══════════════════════════

const _dayLabels = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

String _hhmm(String s) => s.length >= 5 ? s.substring(0, 5) : s;

class AssignmentRulesPage extends StatefulWidget {
  const AssignmentRulesPage({super.key});
  @override
  State<AssignmentRulesPage> createState() => _AssignmentRulesPageState();
}

class _AssignmentRulesPageState extends State<AssignmentRulesPage> {
  bool _loading = true;
  bool _saving = false;
  List<Rec> _hours = [];
  List<Rec> _holidays = [];

  final _sla = TextEditingController();
  final _aiTakeover = TextEditingController();
  final _gap = TextEditingController();
  final _timeout = TextEditingController();
  final _rounds = TextEditingController();
  final _dupWindow = TextEditingController();
  final _wStart = TextEditingController();
  final _wEnd = TextEditingController();
  final _timezone = TextEditingController();
  final _wAvail = TextEditingController();
  final _wMaxLeads = TextEditingController();
  final _wPerf = TextEditingController();
  final _wWorkload = TextEditingController();

  String _strategy = 'round_robin';
  String _notificationMode = 'auto';
  String _duplicateAction = 'assign_same_staff';
  bool _autoAssign = true;
  Set<int> _workingDays = {1, 2, 3, 4, 5};

  @override
  void dispose() {
    for (final c in [_sla, _aiTakeover, _gap, _timeout, _rounds, _dupWindow, _wStart, _wEnd, _timezone, _wAvail, _wMaxLeads, _wPerf, _wWorkload]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        Api.one('/lead-assignment-rules'),
        Api.one('/working-hours'),
      ]);
      final rule = results[0];
      final wh = results[1];
      setState(() {
        _strategy = str(rule['strategy'], 'round_robin');
        _notificationMode = str(rule['notification_mode'], 'auto');
        _duplicateAction = str(rule['duplicate_action'], 'assign_same_staff');
        _autoAssign = rule['auto_assign_enabled'] != false;
        _sla.text = str(rule['sla_minutes'], '');
        _aiTakeover.text = str(rule['ai_takeover_after_minutes'], '');
        _gap.text = str(rule['notification_gap_seconds'], '');
        _timeout.text = str(rule['notification_timeout_seconds'], '');
        _rounds.text = str(rule['max_notification_rounds'], '');
        _dupWindow.text = str(rule['duplicate_window_days'], '');
        _wStart.text = _hhmm(str(rule['working_hours_start'], '09:00'));
        _wEnd.text = _hhmm(str(rule['working_hours_end'], '18:00'));
        _timezone.text = str(rule['timezone'], '');
        _wAvail.text = str(rule['weight_availability'], '');
        _wMaxLeads.text = str(rule['weight_max_leads'], '');
        _wPerf.text = str(rule['weight_performance'], '');
        _wWorkload.text = str(rule['weight_workload'], '');
        final days = rule['working_days'];
        if (days is List) _workingDays = days.map((d) => int.tryParse('$d') ?? -1).where((d) => d >= 0).toSet();
        final hoursList = wh['hours'];
        _hours = hoursList is List ? hoursList.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList() : [];
        final holidaysList = wh['holidays'];
        _holidays = holidaysList is List ? holidaysList.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList() : [];
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _saveRule() async {
    setState(() => _saving = true);
    final ok = await runAction(context, () => Api.post('/lead-assignment-rules', data: {
      'auto_assign_enabled': _autoAssign,
      'strategy': _strategy,
      'weight_availability': num.tryParse(_wAvail.text) ?? 0,
      'weight_max_leads': num.tryParse(_wMaxLeads.text) ?? 0,
      'weight_performance': num.tryParse(_wPerf.text) ?? 0,
      'weight_workload': num.tryParse(_wWorkload.text) ?? 0,
      'sla_minutes': num.tryParse(_sla.text),
      'ai_takeover_after_minutes': num.tryParse(_aiTakeover.text),
      'notification_mode': _notificationMode,
      'notification_gap_seconds': num.tryParse(_gap.text),
      'notification_timeout_seconds': num.tryParse(_timeout.text),
      'max_notification_rounds': num.tryParse(_rounds.text),
      'duplicate_window_days': num.tryParse(_dupWindow.text),
      'duplicate_action': _duplicateAction,
      'working_hours_start': _wStart.text,
      'working_hours_end': _wEnd.text,
      'working_days': _workingDays.toList()..sort(),
      'timezone': _timezone.text,
    }), success: 'Assignment rules saved');
    setState(() => _saving = false);
    if (ok) _load();
  }

  Future<void> _saveHours() async {
    final ok = await runAction(context, () => Api.raw.put('/working-hours', data: {
      'hours': _hours.map((h) => {
            'weekday': h['weekday'],
            'is_open': h['is_open'],
            'start_time': (h['start_time'] as String?)?.substring(0, 5) ?? '09:00',
            'end_time': (h['end_time'] as String?)?.substring(0, 5) ?? '18:00',
          }).toList(),
    }), success: 'Working hours saved');
    if (ok) _load();
  }

  Future<void> _addHoliday() async {
    final data = <String, dynamic>{};
    final ok = await showFormSheet(
      context,
      title: 'Add holiday',
      fields: (ctx) => [
        FText(label: 'Date (YYYY-MM-DD)', required: true, onSaved: (v) => data['date'] = v),
        FText(label: 'Name', required: true, onSaved: (v) => data['name'] = v),
      ],
      onSubmit: () => Api.post('/working-hours/holidays', data: data),
    );
    if (ok) _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return Scaffold(
      appBar: AppBar(title: const Text('Assignment Rules')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Routing strategy', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Auto-assign enabled'),
            value: _autoAssign,
            onChanged: (v) => setState(() => _autoAssign = v),
          ),
          Row(children: [
            Expanded(
              child: RadioListTile<String>(
                contentPadding: EdgeInsets.zero,
                title: const Text('Round robin'),
                value: 'round_robin',
                groupValue: _strategy,
                onChanged: (v) => setState(() => _strategy = v ?? 'round_robin'),
              ),
            ),
            Expanded(
              child: RadioListTile<String>(
                contentPadding: EdgeInsets.zero,
                title: const Text('Algorithm'),
                value: 'algorithm',
                groupValue: _strategy,
                onChanged: (v) => setState(() => _strategy = v ?? 'round_robin'),
              ),
            ),
          ]),
          if (_strategy == 'algorithm') ...[
            const SizedBox(height: 8),
            Text('Weights (should sum to 100)', style: TextStyle(color: context.mutedColor, fontSize: 12)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: TextField(controller: _wAvail, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Availability', isDense: true))),
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: _wMaxLeads, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Max leads', isDense: true))),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: TextField(controller: _wPerf, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Performance', isDense: true))),
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: _wWorkload, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Workload', isDense: true))),
            ]),
          ],
          const SizedBox(height: 20),
          const Text('SLA & AI takeover', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: TextField(controller: _sla, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'SLA (minutes)', isDense: true))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: _aiTakeover, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'AI takeover (min)', isDense: true))),
          ]),
          const SizedBox(height: 20),
          const Text('Notifications', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _notificationMode,
            decoration: const InputDecoration(labelText: 'Mode', isDense: true),
            items: const [
              DropdownMenuItem(value: 'auto', child: Text('Auto')),
              DropdownMenuItem(value: 'uber', child: Text('Uber-style (one at a time)')),
              DropdownMenuItem(value: 'hybrid', child: Text('Hybrid')),
            ],
            onChanged: (v) => setState(() => _notificationMode = v ?? 'auto'),
          ),
          if (_notificationMode != 'auto') ...[
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: TextField(controller: _gap, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Gap (sec)', isDense: true))),
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: _timeout, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Timeout (sec)', isDense: true))),
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: _rounds, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Max rounds', isDense: true))),
            ]),
          ],
          const SizedBox(height: 20),
          const Text('Duplicate handling', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _duplicateAction,
                decoration: const InputDecoration(labelText: 'Action', isDense: true),
                items: const [
                  DropdownMenuItem(value: 'assign_same_staff', child: Text('Same staff')),
                  DropdownMenuItem(value: 'create_new', child: Text('Create new')),
                  DropdownMenuItem(value: 'merge', child: Text('Merge')),
                  DropdownMenuItem(value: 'notify_admin', child: Text('Notify admin')),
                ],
                onChanged: (v) => setState(() => _duplicateAction = v ?? 'assign_same_staff'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: _dupWindow, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Window (days)', isDense: true))),
          ]),
          const SizedBox(height: 20),
          const Text('Working days & timezone', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 8),
          Wrap(spacing: 6, children: [
            for (var d = 0; d < 7; d++)
              FilterChip(
                label: Text(_dayLabels[d]),
                selected: _workingDays.contains(d),
                onSelected: (v) => setState(() => v ? _workingDays.add(d) : _workingDays.remove(d)),
              ),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: TextField(controller: _wStart, decoration: const InputDecoration(labelText: 'Start (HH:mm)', isDense: true))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: _wEnd, decoration: const InputDecoration(labelText: 'End (HH:mm)', isDense: true))),
          ]),
          const SizedBox(height: 12),
          TextField(controller: _timezone, decoration: const InputDecoration(labelText: 'Timezone', isDense: true)),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _saving ? null : _saveRule,
            child: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Save assignment rules'),
          ),
          const SizedBox(height: 32),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('Office weekly hours', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            TextButton(onPressed: _saveHours, child: const Text('Save hours')),
          ]),
          const SizedBox(height: 8),
          for (final h in _hours) _HourRow(row: h, onChanged: (updated) {
            setState(() {
              final i = _hours.indexWhere((x) => x['weekday'] == h['weekday']);
              if (i != -1) _hours[i] = updated;
            });
          }),
          const SizedBox(height: 24),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('Holidays', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            TextButton.icon(onPressed: _addHoliday, icon: const Icon(Icons.add_rounded, size: 18), label: const Text('Add')),
          ]),
          const SizedBox(height: 8),
          if (_holidays.isEmpty)
            Text('No holidays configured', style: TextStyle(color: context.mutedColor, fontSize: 13))
          else
            ..._holidays.map((h) => KvRow(str(h['name']), str(h['date']))),
        ],
      ),
    );
  }
}

class _HourRow extends StatefulWidget {
  const _HourRow({required this.row, required this.onChanged});
  final Rec row;
  final void Function(Rec) onChanged;

  @override
  State<_HourRow> createState() => _HourRowState();
}

class _HourRowState extends State<_HourRow> {
  late final _start = TextEditingController(text: (widget.row['start_time'] as String?)?.substring(0, 5) ?? '09:00');
  late final _end = TextEditingController(text: (widget.row['end_time'] as String?)?.substring(0, 5) ?? '18:00');

  @override
  void dispose() {
    _start.dispose();
    _end.dispose();
    super.dispose();
  }

  void _emit() {
    widget.onChanged({
      ...widget.row,
      'start_time': _start.text,
      'end_time': _end.text,
    });
  }

  @override
  Widget build(BuildContext context) {
    final weekday = widget.row['weekday'] as int? ?? 0;
    final isOpen = widget.row['is_open'] == true;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        SizedBox(width: 44, child: Text(_dayLabels[weekday], style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
        Switch(
          value: isOpen,
          onChanged: (v) => widget.onChanged({...widget.row, 'is_open': v}),
        ),
        if (isOpen) ...[
          Expanded(
            child: TextField(controller: _start, decoration: const InputDecoration(isDense: true), onChanged: (_) => _emit()),
          ),
          const SizedBox(width: 6),
          const Text('–'),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(controller: _end, decoration: const InputDecoration(isDense: true), onChanged: (_) => _emit()),
          ),
        ] else
          Expanded(child: Text('Closed', style: TextStyle(color: context.mutedColor))),
      ]),
    );
  }
}
