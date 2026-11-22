import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:unichat_mobile_app/core/network/api.dart';
import 'package:unichat_mobile_app/core/permissions/permission_guard.dart';
import 'package:unichat_mobile_app/features/attendance/attendance_actions.dart' show formatDelay;
import 'package:unichat_mobile_app/core/theme/app_theme.dart';
import 'package:unichat_mobile_app/features/modules/_shared.dart';

// Statistics → Attendance (per-staff today) and Statistics → Sales team (per-staff report).

final _allStaffProvider =
    FutureProvider((ref) => Api.list('/staff', query: {'per_page': 100}));
final _salesTeamProvider = FutureProvider.family<Map<String, dynamic>, String>(
    (ref, range) => Api.one('/analytics/sales-team', query: {'range': range}));

num _n(Object? v) => v is num ? v : (num.tryParse('${v ?? ''}') ?? 0);

class _PillDrop<T> extends StatelessWidget {
  const _PillDrop({required this.value, required this.items, required this.onChanged});
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  @override
  Widget build(BuildContext context) => Container(
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

Widget _card(BuildContext context, {required Widget child}) => Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.lineColor),
      ),
      child: child,
    );

Widget _pill(String text, Color c) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(color: c.withOpacity(0.14), borderRadius: BorderRadius.circular(99)),
      child: Text(text, style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w700)),
    );

Widget _avatar(String name, Color c) => CircleAvatar(
      radius: 17,
      backgroundColor: c.withOpacity(0.16),
      child: Text(name.isEmpty ? '?' : name.trim()[0].toUpperCase(),
          style: TextStyle(color: c, fontWeight: FontWeight.w800)),
    );

// ───────────────────────── Attendance ─────────────────────────

String _hm(Object? iso) {
  final d = DateTime.tryParse('${iso ?? ''}')?.toLocal();
  if (d == null) return '—';
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return '$h:${d.minute.toString().padLeft(2, '0')} ${d.hour >= 12 ? 'PM' : 'AM'}';
}

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

const _mn = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
String _pretty(DateTime d) => '${d.day} ${_mn[d.month - 1]} ${d.year}';

/// Everyone's attendance rows for one date (GET /hr/attendance?date=…).
final _attDayProvider = FutureProvider.family<List<Map<String, dynamic>>, String>(
    (ref, date) => Api.list('/hr/attendance', query: {'date': date, 'per_page': 300}));

/// Per-staff month summary incl. attendance % (GET /hr/attendance/payroll?month=YYYY-MM).
final _attMonthProvider = FutureProvider.family<List<Map<String, dynamic>>, String>(
    (ref, month) => Api.list('/hr/attendance/payroll', query: {'month': month}));

class AttendanceReport extends ConsumerStatefulWidget {
  const AttendanceReport({super.key});
  @override
  ConsumerState<AttendanceReport> createState() => _AttendanceReportState();
}

class _AttendanceReportState extends ConsumerState<AttendanceReport> {
  String _f = 'all';
  DateTime _date = DateTime.now();
  static const _filters = [
    ('all', 'All'),
    ('ontime', 'On time'),
    ('late', 'Late'),
    ('working', 'Working now'),
    ('out', 'Clocked out'),
    ('leave', 'On leave'),
    ('notin', 'Not clocked in'),
  ];

  bool get _isToday {
    final n = DateTime.now();
    return _date.year == n.year && _date.month == n.month && _date.day == n.day;
  }

  bool _match(Map r) {
    final inAt = r['clock_in_at'] != null, outAt = r['clock_out_at'] != null;
    final late = _n(r['late_minutes']) > 0;
    switch (_f) {
      case 'ontime': return inAt && !late;
      case 'late': return inAt && late;
      case 'working': return inAt && !outAt;
      case 'out': return outAt;
      case 'leave': return r['status'] == 'on_leave';
      case 'notin': return !inAt && r['status'] != 'on_leave';
      default: return true;
    }
  }

  Future<void> _pick() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (d != null) setState(() => _date = d);
  }

  void _shift(int days) {
    final n = _date.add(Duration(days: days));
    if (n.isAfter(DateTime.now())) return;
    setState(() => _date = n);
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(_attDayProvider(_ymd(_date)));
    final staff = ref.watch(_allStaffProvider).value ?? const <Map<String, dynamic>>[];
    final month = ref.watch(_attMonthProvider('${_date.year}-${_date.month.toString().padLeft(2, '0')}')).value;
    final monthBy = <String, Map>{
      for (final m in month ?? const <Map<String, dynamic>>[])
        '${(m['user'] is Map ? (m['user'] as Map)['id'] : '')}': m,
    };
    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(20),
        child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
      ),
      error: (_, __) => const SizedBox.shrink(),
      data: (day) {
        // Every member, not just those with a row that day: staff with no punch get a
        // placeholder row so "Not in" people show up too.
        final seen = <String>{
          for (final r in day) '${r['user_id'] ?? (r['user'] is Map ? (r['user'] as Map)['id'] : '')}',
        };
        final all = <Map>[
          ...day,
          for (final s in staff)
            if (s['is_active'] != false && !seen.contains('${s['id']}'))
              {'user': {'id': s['id'], 'name': s['name']}, 'clock_in_at': null, 'clock_out_at': null, 'late_minutes': 0, 'breaks': const []},
        ];
        final onTime = all.where((r) => r['clock_in_at'] != null && _n(r['late_minutes']) == 0).length;
        final late = all.where((r) => _n(r['late_minutes']) > 0).length;
        final notIn = all.where((r) => r['clock_in_at'] == null && r['status'] != 'on_leave').length;
        final rows = all.where(_match).toList();
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Date picker row
            Row(children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.chevron_left_rounded),
                onPressed: () => _shift(-1),
              ),
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: _pick,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 12),
                    decoration: BoxDecoration(
                      color: context.lineColor.withOpacity(0.35),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Icon(Icons.calendar_month_rounded, size: 16),
                      const SizedBox(width: 8),
                      Text(_isToday ? 'Today · ${_pretty(_date)}' : _pretty(_date),
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                    ]),
                  ),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.chevron_right_rounded),
                onPressed: _isToday ? null : () => _shift(1),
              ),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: _PillDrop<String>(
                  value: _f,
                  items: [for (final f in _filters) DropdownMenuItem(value: f.$1, child: Text(f.$2))],
                  onChanged: (v) => setState(() => _f = v ?? 'all'),
                ),
              ),
              const SizedBox(width: 8),
              _pill('On time $onTime', const Color(0xFF16A34A)),
              const SizedBox(width: 6),
              _pill('Late $late', const Color(0xFFEA580C)),
              const SizedBox(width: 6),
              _pill('Not in $notIn', const Color(0xFF9CA3AF)),
            ]),
            const SizedBox(height: 10),
            if (rows.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 18),
                child: Center(child: Text('No attendance for this filter',
                    style: TextStyle(color: context.mutedColor, fontSize: 12.5))),
              ),
            for (final r in rows)
              _row(context, r, monthBy['${r['user_id'] ?? (r['user'] is Map ? (r['user'] as Map)['id'] : '')}']),
          ]),
        );
      },
    );
  }

  Widget _row(BuildContext context, Map r, Map? month) {
    final user = r['user'] is Map ? r['user'] as Map : const {};
    final name = '${user['name'] ?? 'Staff'}';
    final inAt = r['clock_in_at'] != null, outAt = r['clock_out_at'] != null;
    final lateMin = _n(r['late_minutes']).toInt();
    final onLeave = r['status'] == 'on_leave';
    final breaks = (r['breaks'] is List ? r['breaks'] as List : const []).whereType<Map>().toList();
    final breakMin = breaks.fold<num>(0, (a, b) => a + _n(b['minutes']));
    final status = onLeave
        ? _pill('On leave', const Color(0xFF7C3AED))
        : !inAt
            ? _pill('Not in', const Color(0xFF9CA3AF))
            : lateMin > 0
                ? _pill('Late ${formatDelay(lateMin)} min', const Color(0xFFEA580C))
                : _pill('On time', const Color(0xFF16A34A));
    Widget kv(IconData i, String t, Color c) => Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(i, size: 14, color: c),
          const SizedBox(width: 4),
          Text(t, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        ]);

    final pct = month == null ? null : _n(month['attendance_pct']).toDouble();
    return _card(
      context,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _avatar(name, const Color(0xFFEC4899)),
          const SizedBox(width: 10),
          Expanded(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700))),
          status,
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 16, runSpacing: 6, children: [
          kv(Icons.login_rounded, 'In ${_hm(r['clock_in_at'])}', const Color(0xFF16A34A)),
          kv(Icons.logout_rounded, outAt ? 'Out ${_hm(r['clock_out_at'])}' : (inAt ? 'Working' : 'Out —'),
              const Color(0xFFDC2626)),
          kv(Icons.free_breakfast_rounded,
              breaks.isEmpty ? 'No breaks' : '${breaks.length} break${breaks.length > 1 ? 's' : ''} · ${breakMin.toInt()} min',
              const Color(0xFF0EA5E9)),
        ]),
        // Each break: type, from–to, minutes (flagged when over the allowed limit)
        for (final b in breaks)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Row(children: [
              Icon(Icons.circle, size: 6, color: context.mutedColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${(b['break_type'] is Map ? (b['break_type'] as Map)['name'] : null) ?? (b['breakType'] is Map ? (b['breakType'] as Map)['name'] : null) ?? 'Break'}'
                  '  ${_hm(b['start_at'])} – ${b['end_at'] == null ? 'ongoing' : _hm(b['end_at'])}',
                  style: TextStyle(color: context.mutedColor, fontSize: 11.5),
                ),
              ),
              Text('${_n(b['minutes']).toInt()} min',
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: (b['over_limit'] == true || b['over_limit'] == 1)
                          ? const Color(0xFFEA580C)
                          : null)),
            ]),
          ),
        // Monthly attendance percentage (present days ÷ working days so far this month)
        if (pct != null) ...[
          const SizedBox(height: 10),
          Row(children: [
            Text('This month', style: TextStyle(color: context.mutedColor, fontSize: 11.5)),
            const Spacer(),
            Text('${_n(month!['present_days']).toInt()}/${_n(month['working_days']).toInt()} days · ${pct.toStringAsFixed(pct % 1 == 0 ? 0 : 1)}%',
                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: (pct / 100).clamp(0, 1).toDouble(),
              minHeight: 6,
              backgroundColor: context.lineColor,
              color: pct >= 90 ? const Color(0xFF16A34A) : (pct >= 70 ? const Color(0xFFF59E0B) : const Color(0xFFDC2626)),
            ),
          ),
        ],
      ]),
    );
  }
}

// ───────────────────────── Sales team ─────────────────────────

const _salesRanges = [
  ('today', 'Today'),
  ('this_week', 'This week'),
  ('this_month', 'This month'),
  ('last_3_months', 'Last 3 months'),
];

class SalesTeamReport extends ConsumerStatefulWidget {
  const SalesTeamReport({super.key});
  @override
  ConsumerState<SalesTeamReport> createState() => _SalesTeamReportState();
}

class _SalesTeamReportState extends ConsumerState<SalesTeamReport> {
  String _range = 'this_month';

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(_salesTeamProvider(_range));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _PillDrop<String>(
          value: _range,
          items: [for (final r in _salesRanges) DropdownMenuItem(value: r.$1, child: Text(r.$2))],
          onChanged: (v) => setState(() => _range = v ?? _range),
        ),
        const SizedBox(height: 10),
        async.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(20),
            child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
          ),
          error: (e, _) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text("Couldn't load sales report — ${apiErrorMessage(e)}",
                style: TextStyle(color: context.mutedColor, fontSize: 12)),
          ),
          data: (d) {
            final staff = (d['staff'] is List ? d['staff'] as List : const []).whereType<Map>().toList();
            if (staff.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 18),
                child: Center(child: Text('No sales activity in this period',
                    style: TextStyle(color: context.mutedColor, fontSize: 12.5))),
              );
            }
            return Column(children: [for (final s in staff) _staffCard(context, s)]);
          },
        ),
      ]),
    );
  }

  Widget _staffCard(BuildContext context, Map s) {
    final name = '${s['name'] ?? 'Staff'}';
    Widget cell(String label, Object? v, Color c, {String? suffix}) => Expanded(
          child: Column(children: [
            Text('${compact(v)}${suffix ?? ''}',
                style: TextStyle(color: c, fontSize: 16, fontWeight: FontWeight.w800)),
            Text(label, style: TextStyle(color: context.mutedColor, fontSize: 10.5)),
          ]),
        );
    final missed = _n(s['missed']);
    return _card(
      context,
      child: Column(children: [
        Row(children: [
          _avatar(name, const Color(0xFF22C55E)),
          const SizedBox(width: 10),
          Expanded(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700))),
          if (missed > 0) _pill('${missed.toInt()} missed', const Color(0xFFDC2626)),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          cell('Leads', s['leads'], const Color(0xFF7C3AED)),
          cell('Converted', s['converted'], const Color(0xFF16A34A)),
          cell('Rejected', s['rejected'], const Color(0xFFDC2626)),
          cell('Pending', s['pending'], const Color(0xFFF59E0B)),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          cell('Follow-ups', s['followups'], const Color(0xFF0EA5E9)),
          cell('Done', s['followups_done'], const Color(0xFF16A34A)),
          cell('Missed', s['missed'], const Color(0xFFDC2626)),
          const Expanded(child: SizedBox.shrink()),
        ]),
      ]),
    );
  }
}


// ───────────────────────── Team (HR · CRM · Leads) ─────────────────────────

/// Mirrors the server's rule for GET /analytics/team-members: company admin / owner, a team head, or anyone with HR / staff-view access.
bool canSeeTeam() =>
    PermissionGuard.isAdmin ||
    PermissionGuard.role.toLowerCase() == 'team_lead' ||
    PermissionGuard.can('hr.manage') ||
    PermissionGuard.can('hr.attendance.view_all') ||
    PermissionGuard.can('staff.view');

/// Every active member with their own figures for one section ('hr' | 'crm' | 'leads').
final teamMembersProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, String>(
    (ref, section) => Api.one('/analytics/team-members', query: {'section': section}),
    // a refusal (403) must collapse the block at once — Riverpod 3 would otherwise retry it for minutes under a spinner
    retry: (count, error) => null);

class TeamMembersPanel extends ConsumerStatefulWidget {
  const TeamMembersPanel({super.key, this.initial = 'hr'});
  final String initial;
  @override
  ConsumerState<TeamMembersPanel> createState() => _TeamMembersPanelState();
}

class _TeamMembersPanelState extends ConsumerState<TeamMembersPanel> {
  late String _tab = widget.initial;
  static const _tabs = [('hr', 'HR'), ('crm', 'CRM'), ('leads', 'Leads')];

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(teamMembersProvider(_tab));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          for (final t in _tabs) ...[
            ChoiceChip(
              key: ValueKey('team-tab-${t.$1}'),
              label: Text(t.$2),
              selected: _tab == t.$1,
              onSelected: (_) => setState(() => _tab = t.$1),
              visualDensity: VisualDensity.compact,
            ),
            const SizedBox(width: 8),
          ],
        ]),
        const SizedBox(height: 10),
        async.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(20),
            child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
          ),
          // 403 for people who may not see the team — show nothing rather than an error
          error: (_, __) => const SizedBox.shrink(),
          data: (d) {
            final s = d['summary'] is Map ? d['summary'] as Map : const {};
            final members = (d['members'] is List ? d['members'] as List : const []).whereType<Map>().toList();
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 6, runSpacing: 6, children: _summary(s)),
              const SizedBox(height: 8),
              Text('${members.length} members', key: const ValueKey('team-count'),
                  style: TextStyle(color: context.mutedColor, fontSize: 12)),
              const SizedBox(height: 4),
              for (final m in members) _member(context, m),
            ]);
          },
        ),
      ]),
    );
  }

  List<Widget> _summary(Map s) {
    String v(String k) => '${_n(s[k]).toInt()}';
    return switch (_tab) {
      'hr' => [
          _pill('Working ${v('working')}', const Color(0xFF16A34A)),
          _pill('Out ${v('out')}', const Color(0xFF6B7280)),
          _pill('Leave ${v('on_leave')}', const Color(0xFF7C3AED)),
          _pill('Not in ${v('not_in')}', const Color(0xFF9CA3AF)),
          _pill('Late ${v('late')}', const Color(0xFFEA580C)),
        ],
      'crm' => [
          _pill('Open deals ${v('open_deals')}', const Color(0xFF2563EB)),
          _pill('Won ${v('won_month')}', const Color(0xFF16A34A)),
          _pill('Tasks ${v('open_tasks')}', const Color(0xFF6B7280)),
          _pill('Overdue ${v('overdue_tasks')}', const Color(0xFFDC2626)),
        ],
      _ => [
          _pill('Assigned ${v('assigned')}', const Color(0xFF2563EB)),
          _pill('Active ${v('active')}', const Color(0xFF6B7280)),
          _pill('Enrolled ${v('enrolled')}', const Color(0xFF16A34A)),
          _pill('New today ${v('new_today')}', const Color(0xFF0EA5E9)),
          _pill('${_n(s['conversion'])}%', const Color(0xFFEA580C)),
        ],
    };
  }

  Widget _member(BuildContext context, Map m) {
    final name = '${m['name'] ?? 'Staff'}';
    final sub = [m['role'], m['department']].where((x) => x != null && '$x'.isNotEmpty).join(' · ');
    Widget status;
    switch (_tab) {
      case 'hr':
        final late = _n(m['late_minutes']).toInt();
        final st = '${m['state']}';
        final (label, color) = switch (st) {
          'working' => ('Working', const Color(0xFF16A34A)),
          'out' => ('Clocked out', const Color(0xFF6B7280)),
          'on_leave' => ('On leave', const Color(0xFF7C3AED)),
          _ => ('Not in', const Color(0xFF9CA3AF)),
        };
        status = Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, alignment: WrapAlignment.end, children: [
          if (m['clock_in_at'] != null)
            Text(_hm(m['clock_in_at']) + (m['clock_out_at'] != null ? ' – ${_hm(m['clock_out_at'])}' : ''),
                style: TextStyle(color: context.mutedColor, fontSize: 11)),
          if (late > 0) _pill('${formatDelay(late)} min late', const Color(0xFFEA580C)),
          _pill(label, color),
        ]);
      case 'crm':
        final over = _n(m['overdue_tasks']).toInt();
        status = Text('${_n(m['open_deals']).toInt()} deals · ${_n(m['open_tasks']).toInt()} tasks${over > 0 ? ' · $over overdue' : ''}',
            textAlign: TextAlign.end, style: const TextStyle(fontSize: 11.5));
      default:
        status = Text('${_n(m['assigned']).toInt()} assigned · ${_n(m['enrolled']).toInt()} enrolled (${_n(m['conversion'])}%)',
            textAlign: TextAlign.end, style: const TextStyle(fontSize: 11.5));
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        _avatar(name, const Color(0xFF4F46E5)),
        const SizedBox(width: 10),
        Expanded(
          flex: 5,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(m['is_me'] == true ? '$name (you)' : name,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            if (sub.isNotEmpty) Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: context.mutedColor, fontSize: 11)),
          ]),
        ),
        Expanded(flex: 6, child: Align(alignment: Alignment.centerRight, child: status)),
      ]),
    );
  }
}
