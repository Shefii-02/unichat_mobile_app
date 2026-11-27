import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:unichat_mobile_app/core/constants/app_colors.dart';
import 'package:unichat_mobile_app/core/permissions/permission_guard.dart';
import 'package:unichat_mobile_app/core/widgets/app_empty_state.dart';
import 'package:unichat_mobile_app/features/modules/_shared.dart';

/// Calls logged on leads: filter by direction (incoming / outgoing / missed / received), outcome, a date range picked on ONE calendar, and search.
/// "Mine" by default; people who can see every lead can switch to the whole team.
class CallLogsPage extends StatefulWidget {
  const CallLogsPage({super.key, this.direction, this.today = false});
  /// Opens with this direction picked (incoming | outgoing | missed | received) and/or only today's calls — the Sales home's round icons use it.
  final String? direction;
  final bool today;
  @override
  State<CallLogsPage> createState() => _CallLogsPageState();
}

class _CallLogsPageState extends State<CallLogsPage> {
  List<Map<String, dynamic>> _rows = [];
  Map<String, dynamic> _counts = {};
  bool _loading = true;
  String? _error;
  String _dir = 'all';            // all | incoming | outgoing | missed | received
  String? _outcome;
  DateTimeRange? _range;
  bool _team = false;
  String _q = '';
  Timer? _debounce;

  static const _outcomes = ['connected', 'not_reachable', 'callback', 'interested', 'not_interested', 'wrong_number'];

  @override
  void initState() {
    super.initState();
    _dir = widget.direction ?? 'all';
    if (widget.today) {
      final n = DateTime.now();
      _range = DateTimeRange(start: DateTime(n.year, n.month, n.day), end: n);
    }
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  String _day(DateTime x) => x.toIso8601String().substring(0, 10);

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await Api.raw.get('/leads/call-logs', queryParameters: {
        if (_dir == 'incoming' || _dir == 'outgoing' || _dir == 'missed') 'direction': _dir,
        if (_dir == 'received') 'status': 'received',
        if (_outcome != null) 'outcome': _outcome,
        if (_range != null) 'from': _day(_range!.start),
        if (_range != null) 'to': _day(_range!.end),
        if (_team) 'scope': 'all',
        if (_q.isNotEmpty) 'q': _q,
      });
      final d = res.data as Map;
      if (!mounted) return;
      setState(() {
        _rows = ((d['data'] as List?) ?? const []).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
        _counts = (d['counts'] as Map?)?.cast<String, dynamic>() ?? {};
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = apiErrorMessage(e); });
    }
  }

  void _set(VoidCallback f) {
    setState(f);
    _load();
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
      initialDateRange: _range,
      helpText: 'Calls from — to',
    );
    if (r != null) _set(() => _range = r);
  }

  ({IconData icon, Color color, String label}) _kind(Map<String, dynamic> a) {
    switch ('${a['direction']}') {
      case 'incoming':
        return (icon: Icons.call_received_rounded, color: const Color(0xFF16A34A), label: 'Incoming');
      case 'missed':
        return (icon: Icons.call_missed_rounded, color: const Color(0xFFDC2626), label: 'Missed');
      default:
        return (icon: Icons.call_made_rounded, color: const Color(0xFF2563EB), label: 'Outgoing');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!PermissionGuard.can('leads.view')) {
      return Scaffold(appBar: AppBar(title: const Text('Call logs')), body: const Center(child: Text("You don't have access to this section")));
    }
    final chips = <(String, String, int?)>[
      ('all', 'All', _counts['all'] as int?),
      ('incoming', 'Incoming', _counts['incoming'] as int?),
      ('outgoing', 'Outgoing', _counts['outgoing'] as int?),
      ('missed', 'Missed', _counts['missed'] as int?),
      ('received', 'Received', _counts['received'] as int?),
    ];
    String d(DateTime x) => '${x.day}/${x.month}/${x.year % 100}';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Call logs'),
        actions: [
          if (PermissionGuard.can('leads.view_all'))
            TextButton(onPressed: () => _set(() => _team = !_team), child: Text(_team ? 'Whole team' : 'Mine')),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: TextField(
            decoration: const InputDecoration(hintText: 'Search name or number…', prefixIcon: Icon(Icons.search, color: AppColors.textLight), isDense: true),
            onChanged: (v) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 350), () => _set(() => _q = v.trim()));
            },
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(children: [
            for (final (k, label, n) in chips)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(label: Text(n == null ? label : '$label · $n'), selected: _dir == k, onSelected: (_) => _set(() => _dir = k), visualDensity: VisualDensity.compact),
              ),
          ]),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(children: [
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: FilterChip(
                avatar: const Icon(Icons.date_range_rounded, size: 16),
                label: Text(_range == null ? 'Date range' : '${d(_range!.start)} – ${d(_range!.end)}'),
                selected: _range != null,
                onSelected: (_) => _pickRange(),
                visualDensity: VisualDensity.compact,
              ),
            ),
            for (final (label, from) in [('Today', 0), ('7 days', 6), ('30 days', 29)])
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ActionChip(
                  label: Text(label),
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    final now = DateTime.now();
                    _set(() => _range = DateTimeRange(start: DateTime(now.year, now.month, now.day).subtract(Duration(days: from)), end: now));
                  },
                ),
              ),
            PopupMenuButton<String?>(
              onSelected: (v) => _set(() => _outcome = v),
              itemBuilder: (_) => [
                const PopupMenuItem<String?>(value: null, child: Text('Any outcome')),
                for (final o in _outcomes) PopupMenuItem<String?>(value: o, child: Text(o.replaceAll('_', ' '))),
              ],
              child: Chip(
                avatar: const Icon(Icons.flag_outlined, size: 16),
                label: Text(_outcome == null ? 'Outcome' : _outcome!.replaceAll('_', ' ')),
                visualDensity: VisualDensity.compact,
                backgroundColor: _outcome == null ? null : AppColors.primary.withValues(alpha: 0.15),
              ),
            ),
            if (_range != null || _outcome != null || _dir != 'all')
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: ActionChip(label: const Text('Clear'), visualDensity: VisualDensity.compact, onPressed: () => _set(() { _range = null; _outcome = null; _dir = 'all'; })),
              ),
          ]),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: _error != null
              ? Center(child: Text(_error!))
              : _loading && _rows.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : _rows.isEmpty
                      ? const AppEmptyState(icon: Icons.call_outlined, title: 'No calls', subtitle: 'No calls match these filters.')
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView.separated(
                            itemCount: _rows.length,
                            separatorBuilder: (_, __) => const Divider(height: 1, indent: 68),
                            itemBuilder: (_, i) {
                              final a = _rows[i];
                              final k = _kind(a);
                              final at = DateTime.tryParse(str(a['happened_at']))?.toLocal();
                              final secs = int.tryParse('${a['duration_seconds'] ?? ''}') ?? 0;
                              final outcome = str(a['outcome']).replaceAll('_', ' ');
                              final name = str(a['contact_name']).isEmpty ? str(a['contact_phone']) : str(a['contact_name']);
                              return ListTile(
                                onTap: () => a['lead_id'] == null ? null : context.push('/lead-detail/${a['lead_id']}'),
                                leading: CircleAvatar(backgroundColor: k.color.withValues(alpha: 0.12), child: Icon(k.icon, color: k.color, size: 20)),
                                title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, color: a['direction'] == 'missed' ? const Color(0xFFDC2626) : null)),
                                subtitle: Text(
                                  [k.label, if (outcome.isNotEmpty) outcome, if (secs > 0) '${secs ~/ 60}m ${secs % 60}s', if (_team && str(a['by']).isNotEmpty) 'by ${a['by']}'].join(' · '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: Text(
                                  at == null ? '' : '${at.day}/${at.month}\n${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}',
                                  textAlign: TextAlign.right,
                                  style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                                ),
                              );
                            },
                          ),
                        ),
        ),
      ]),
    );
  }
}
