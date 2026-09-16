// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'module_providers.dart';
import '_shared.dart';

/// HR Administration — everything a manager needs beyond their own self-service tabs
/// (Home/Attendance/Target/Payroll): team attendance, leave approvals, payroll runs,
/// sales, incentives, per-staff setup, and break/leave-type + office configuration.
/// Every tab is server-permission-gated already (hr.manage / staff.manage /
/// hr.leave.approve) — this page assumes the caller already passed the `/hr` module's own
/// visibility check to get here.
class HrAdminPage extends StatelessWidget {
  const HrAdminPage({super.key, this.initialTabIndex = 0});

  /// Lets a Quick Links tile (see AppModules — "Leave Requests", "Staff Setups", etc. each
  /// deep-link straight to their own tab via `/hr?tab=N`) land directly on the right tab
  /// instead of always opening on Attendance.
  final int initialTabIndex;

  static const _tabs = [
    'Attendance', 'Leave', 'Payroll', 'Sales', 'Incentives', 'Staff Setup',
    'Break Types', 'Leave Types', 'Office',
  ];

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      initialIndex: initialTabIndex.clamp(0, _tabs.length - 1),
      length: _tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('HR Administration'),
          bottom: TabBar(
            isScrollable: true,
            tabs: _tabs.map((t) => Tab(text: t)).toList(),
          ),
        ),
        floatingActionButton: Builder(
          builder: (tabCtx) {
            final idx = DefaultTabController.of(tabCtx).index;
            return switch (idx) {
              2 => FloatingActionButton.extended(
                  onPressed: () => _generatePayrollRun(tabCtx),
                  icon: const Icon(Icons.receipt_long_rounded),
                  label: const Text('Generate run'),
                ),
              3 => FloatingActionButton.extended(
                  onPressed: () => _recordSale(tabCtx),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Record sale'),
                ),
              6 => FloatingActionButton(onPressed: () => _editBreakType(tabCtx), child: const Icon(Icons.add_rounded)),
              7 => FloatingActionButton(onPressed: () => _editLeaveType(tabCtx), child: const Icon(Icons.add_rounded)),
              _ => const SizedBox.shrink(),
            };
          },
        ),
        body: const TabBarView(children: [
          _TeamAttendanceTab(),
          _LeaveTab(),
          _PayrollTab(),
          _SalesTab(),
          _IncentivesTab(),
          _StaffSetupTab(),
          _BreakTypesTab(),
          _LeaveTypesTab(),
          _OfficeTab(),
        ]),
      ),
    );
  }
}

// ══════════════════════════ Attendance (team, today) ══════════════════════════

class _TeamAttendanceTab extends ConsumerWidget {
  const _TeamAttendanceTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ProviderList(
      provider: hrTeamAttendanceTodayProvider,
      emptyLabel: 'No attendance records for today',
      emptyIcon: Icons.groups_rounded,
      header: const _ReopenRequestsHeader(),
      tile: (context, r) {
        final u = (r['user'] is Map) ? (r['user'] as Map) : const {};
        return RecordCard(
          title: str(u['name'], 'Staff'),
          subtitle: str(u['department'], ''),
          leadingIcon: Icons.badge_rounded,
          onTap: () => _editAttendance(context, ref, r, u),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                StatusPill(str(r['status'], 'absent')),
                if (r['clock_in_at'] != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(when(r['clock_in_at']), style: TextStyle(fontSize: 11, color: context.mutedColor)),
                  ),
              ],
            ),
            IconButton(
              icon: const Icon(Icons.edit_rounded, size: 18),
              tooltip: 'Edit attendance',
              onPressed: () => _editAttendance(context, ref, r, u),
            ),
          ]),
        );
      },
    );
  }

  static String _timeOnly(Object? iso) {
    if (iso == null) return '';
    final d = DateTime.tryParse('$iso');
    if (d == null) return '';
    final l = d.toLocal();
    return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }

  /// Converts a `work_date` ("YYYY-MM-DD") + a locally-edited "HH:mm" into a UTC ISO
  /// instant, so the edit is correct regardless of the device's timezone vs the
  /// server's — sending a naive "date time" string for the server to parse would
  /// silently shift by the device's UTC offset instead.
  static String? _localTimeToUtcIso(String workDate, String hhmm) {
    if (hhmm.trim().isEmpty) return null;
    final t = hhmm.split(':');
    final d = workDate.split('-');
    if (t.length != 2 || d.length != 3) return null;
    final h = int.tryParse(t[0]);
    final m = int.tryParse(t[1]);
    final y = int.tryParse(d[0]);
    final mo = int.tryParse(d[1]);
    final da = int.tryParse(d[2]);
    if ([h, m, y, mo, da].any((v) => v == null)) return null;
    return DateTime(y!, mo!, da!, h!, m!).toUtc().toIso8601String();
  }

  Future<void> _editAttendance(BuildContext context, WidgetRef ref, Rec r, Map u) async {
    final workDate = str(r['work_date'], DateTime.now().toIso8601String().substring(0, 10));
    final data = <String, dynamic>{};
    final ok = await showFormSheet(
      context,
      title: 'Edit attendance — ${str(u['name'], 'Staff')}',
      fields: (ctx) => [
        FText(
          label: 'Clock in (HH:mm, blank = not clocked in)',
          initial: _timeOnly(r['clock_in_at']),
          onSaved: (v) => data['clock_in_at'] = _localTimeToUtcIso(workDate, v),
        ),
        FText(
          label: 'Clock out (HH:mm, blank = allow clocking in again today)',
          initial: _timeOnly(r['clock_out_at']),
          onSaved: (v) => data['clock_out_at'] = _localTimeToUtcIso(workDate, v),
        ),
        FSelect<String>(
          label: 'Status',
          options: const ['present', 'absent', 'on_leave', 'half_day', 'weekly_off'],
          initial: str(r['status'], 'present'),
          onSaved: (v) => data['status'] = v ?? 'present',
        ),
        FText(
          label: 'Note (shown to the staff member)',
          initial: r['note_message'] as String?,
          onSaved: (v) => v.isEmpty ? null : data['note_message'] = v,
        ),
      ],
      onSubmit: () => Api.patch('/hr/attendance/${r['id']}', data: data),
    );
    if (ok) ref.invalidate(hrTeamAttendanceTodayProvider);
  }
}

/// Pending "I accidentally clocked out" requests, shown above today's attendance list —
/// approving clears clock_out_at server-side (see AttendanceController::reviewReopen) so the
/// staff member can clock back in; rejecting just closes the request out.
class _ReopenRequestsHeader extends ConsumerWidget {
  const _ReopenRequestsHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(hrReopenRequestsProvider);
    final rows = async.maybeWhen(data: (d) => d, orElse: () => const <Rec>[]);
    if (rows.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Reopen requests',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: context.mutedColor, letterSpacing: 0.4)),
          const SizedBox(height: 8),
          ...rows.map((r) {
            final u = (r['user'] is Map) ? (r['user'] as Map) : const {};
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: RecordCard(
                title: str(u['name'], 'Staff'),
                subtitle: str(r['reopen_reason'], ''),
                leadingIcon: Icons.lock_reset_rounded,
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                    icon: const Icon(Icons.check_circle_outline_rounded, color: AppPalette.success),
                    tooltip: 'Approve — clear the clock-out so they can clock back in',
                    onPressed: () => _review(context, ref, r['id'], 'approved'),
                  ),
                  IconButton(
                    icon: const Icon(Icons.cancel_outlined, color: AppPalette.danger),
                    tooltip: 'Reject',
                    onPressed: () => _review(context, ref, r['id'], 'rejected'),
                  ),
                ]),
              ),
            );
          }),
          const Divider(height: 20),
        ],
      ),
    );
  }

  Future<void> _review(BuildContext context, WidgetRef ref, int id, String decision) async {
    final ok = await runAction(
      context,
      () => Api.post('/hr/attendance/$id/reopen', data: {'decision': decision}),
      success: decision == 'approved' ? 'Reopened — they can clock in again.' : 'Rejected',
    );
    if (ok) {
      ref.invalidate(hrReopenRequestsProvider);
      ref.invalidate(hrTeamAttendanceTodayProvider);
    }
  }
}

// ══════════════════════════ Leave (approve/reject) ══════════════════════════

class _LeaveTab extends ConsumerWidget {
  const _LeaveTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ProviderList(
      provider: hrLeaveTeamProvider,
      emptyLabel: 'No leave requests',
      emptyIcon: Icons.beach_access_rounded,
      tile: (context, l) {
        final user = (l['user'] is Map) ? (l['user'] as Map) : const {};
        final leaveType = (l['leave_type'] is Map) ? (l['leave_type'] as Map) : const {};
        final pending = str(l['status'], 'pending') == 'pending';
        return RecordCard(
          title: '${str(user['name'], 'Staff')} · ${str(leaveType['name'], 'Leave')}',
          subtitle: '${str(l['start_date'])} → ${str(l['end_date'])}${l['reason'] != null ? ' · ${l['reason']}' : ''}',
          leadingIcon: Icons.beach_access_rounded,
          trailing: pending
              ? Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                    icon: const Icon(Icons.check_circle_outline_rounded, color: AppPalette.success),
                    onPressed: () => _review(context, ref, l['id'], 'approved'),
                  ),
                  IconButton(
                    icon: const Icon(Icons.cancel_outlined, color: AppPalette.danger),
                    onPressed: () => _review(context, ref, l['id'], 'rejected'),
                  ),
                ])
              : StatusPill(str(l['status'])),
        );
      },
    );
  }

  Future<void> _review(BuildContext context, WidgetRef ref, int id, String decision) async {
    final ok = await runAction(context, () => Api.post('/hr/leave/$id/review', data: {'decision': decision}),
        success: decision == 'approved' ? 'Approved' : 'Rejected');
    if (ok) ref.invalidate(hrLeaveTeamProvider);
  }
}

// ══════════════════════════ Payroll ══════════════════════════

class _PayrollTab extends ConsumerWidget {
  const _PayrollTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ProviderList(
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

class _SalesTab extends ConsumerWidget {
  const _SalesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(hrSalesSummaryProvider);
    return Column(
      children: [
        summaryAsync.maybeWhen(
          orElse: () => const SizedBox.shrink(),
          data: (res) {
            final rows = (res['data'] is List) ? (res['data'] as List).whereType<Map>().toList() : const <Map>[];
            if (rows.isEmpty) return const SizedBox.shrink();
            return SizedBox(
              height: 96,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.all(12),
                itemCount: rows.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final r = rows[i];
                  final progress = r['progress'];
                  return Container(
                    width: 140,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      border: Border.all(color: context.lineColor),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(str(r['staff_name']), maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
                        const Spacer(),
                        Text(money(r['sold_total']), style: const TextStyle(fontWeight: FontWeight.w800)),
                        Text(progress != null ? '$progress% of target' : 'No target set',
                            style: TextStyle(fontSize: 10.5, color: context.mutedColor)),
                      ],
                    ),
                  );
                },
              ),
            );
          },
        ),
        const Divider(height: 1),
        Expanded(
          child: ProviderList(
            provider: hrSalesAdminProvider,
            emptyLabel: 'No sales recorded',
            emptyIcon: Icons.point_of_sale_rounded,
            tile: (context, s) {
              final staff = (s['staff'] is Map) ? (s['staff'] as Map) : const {};
              final listing = (s['listing'] is Map) ? (s['listing'] as Map) : const {};
              return RecordCard(
                title: str(listing['title'] ?? s['item_label'], 'Sale'),
                subtitle: '${str(staff['name'])} · ${when(s['sold_at'])}',
                leadingIcon: Icons.point_of_sale_rounded,
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(money(s['amount']), style: const TextStyle(fontWeight: FontWeight.w700)),
                  RowMenu(items: [
                    ('Void', Icons.undo_rounded, () async {
                      final sure = await confirm(context, title: 'Void this sale?', destructive: true, confirmLabel: 'Void');
                      if (!sure) return;
                      final ok = await runAction(context, () => Api.delete('/hr/sales/${s['id']}'), success: 'Voided');
                      if (ok) ref.invalidate(hrSalesAdminProvider);
                    }),
                  ]),
                ]),
              );
            },
          ),
        ),
      ],
    );
  }
}

Future<void> _recordSale(BuildContext context) async {
  List<Rec> staff;
  List<Rec> listings;
  try {
    staff = await Api.list('/staff');
    listings = await Api.list('/listings');
  } catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
    return;
  }
  if (!context.mounted) return;

  final data = <String, dynamic>{'sold_at': DateTime.now().toIso8601String()};
  final ok = await showFormSheet(
    context,
    title: 'Record sale',
    submitLabel: 'Record',
    fields: (ctx) => [
      FSelect<Rec>(label: 'Staff', options: staff, labelOf: (s) => str(s['name']), onSaved: (s) => data['staff_id'] = s?['id']),
      if (listings.isNotEmpty)
        FSelect<Rec>(label: 'Catalog item (optional)', options: listings, labelOf: (l) => str(l['title']),
            onSaved: (l) => data['listing_id'] = l?['id']),
      FText(label: 'Item name (if not from catalog)', onSaved: (v) => v.isEmpty ? null : data['item_label'] = v),
      FNumber(label: 'Amount', required: true, onSaved: (v) => data['amount'] = v),
      FText(label: 'Note', onSaved: (v) => v.isEmpty ? null : data['note'] = v),
    ],
    onSubmit: () => Api.post('/hr/sales', data: data),
  );
  if (ok && context.mounted) {
    ProviderScope.containerOf(context, listen: false)
      ..invalidate(hrSalesAdminProvider)
      ..invalidate(hrSalesSummaryProvider);
  }
}

// ══════════════════════════ Incentives (rules + ledger) ══════════════════════════

class _IncentivesTab extends ConsumerWidget {
  const _IncentivesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      children: [
        SectionHeader('Incentive rules',
            action: TextButton(onPressed: () => _editRule(context, ref, null), child: const Text('+ Add'))),
        ref.watch(hrIncentiveRulesProvider).maybeWhen(
          orElse: () => const SizedBox.shrink(),
          data: (rules) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: rules.map((r) {
                final kind = str(r['kind'], 'percentage');
                final label = kind == 'percentage' ? '${str(r['name'])} · ${r['percent']}%' : '${str(r['name'])} · ${money(r['fixed_amount'])}';
                return InputChip(
                  label: Text(label, style: const TextStyle(fontSize: 11.5)),
                  onPressed: () => _editRule(context, ref, r),
                  onDeleted: () async {
                    final ok = await confirm(context, title: 'Delete rule?', destructive: true, confirmLabel: 'Delete');
                    if (!ok) return;
                    final done = await runAction(context, () => Api.delete('/hr/incentive-rules/${r['id']}'), success: 'Deleted');
                    if (done) ref.invalidate(hrIncentiveRulesProvider);
                  },
                );
              }).toList(),
            ),
          ),
        ),
        const SizedBox(height: 8),
        SectionHeader('Ledger', action: TextButton(onPressed: () => _addIncentive(context, ref), child: const Text('+ Add'))),
        ref.watch(hrIncentivesProvider).maybeWhen(
          orElse: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          ),
          data: (rows) {
            if (rows.isEmpty) {
              return Padding(
                padding: const EdgeInsets.all(24),
                child: Text('No incentives recorded', style: TextStyle(color: context.mutedColor)),
              );
            }
            return Column(
              children: rows.map((i) {
                final user = (i['user'] is Map) ? (i['user'] as Map) : const {};
                return RecordCard(
                  title: '${str(user['name'], 'Staff')} · ${str(i['title'])}',
                  subtitle: when(i['earned_on']),
                  leadingIcon: Icons.card_giftcard_rounded,
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(money(i['amount']), style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(width: 6),
                    StatusPill(str(i['status'], 'pending')),
                  ]),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  Future<void> _editRule(BuildContext context, WidgetRef ref, Rec? rule) async {
    final data = <String, dynamic>{};
    final ok = await showFormSheet(
      context,
      title: rule == null ? 'Add incentive rule' : 'Edit incentive rule',
      fields: (ctx) => [
        FText(label: 'Name', initial: rule?['name'] as String?, required: true, onSaved: (v) => data['name'] = v),
        FSelect<String>(label: 'Category', options: const ['service', 'course', 'product', 'other'],
            initial: str(rule?['category'], 'service'), onSaved: (v) => data['category'] = v ?? 'service'),
        FSelect<String>(label: 'Kind', options: const ['percentage', 'fixed'],
            initial: str(rule?['kind'], 'percentage'), onSaved: (v) => data['kind'] = v ?? 'percentage'),
        FNumber(label: 'Percent', initial: rule?['percent'] as num?, onSaved: (v) => data['percent'] = v),
        FNumber(label: 'Fixed amount', initial: rule?['fixed_amount'] as num?, onSaved: (v) => data['fixed_amount'] = v),
      ],
      onSubmit: () => rule == null
          ? Api.post('/hr/incentive-rules', data: data)
          : Api.patch('/hr/incentive-rules/${rule['id']}', data: data),
    );
    if (ok) ref.invalidate(hrIncentiveRulesProvider);
  }

  Future<void> _addIncentive(BuildContext context, WidgetRef ref) async {
    List<Rec> staff;
    try {
      staff = await Api.list('/staff');
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
      return;
    }
    if (!context.mounted) return;
    final data = <String, dynamic>{'earned_on': DateTime.now().toIso8601String()};
    final ok = await showFormSheet(
      context,
      title: 'Add incentive',
      fields: (ctx) => [
        FSelect<Rec>(label: 'Staff', options: staff, labelOf: (s) => str(s['name']), onSaved: (s) => data['user_id'] = s?['id']),
        FText(label: 'Title', required: true, onSaved: (v) => data['title'] = v),
        FNumber(label: 'Amount', onSaved: (v) => data['amount'] = v),
        FText(label: 'Note', onSaved: (v) => v.isEmpty ? null : data['note'] = v),
      ],
      onSubmit: () => Api.post('/hr/incentives', data: data),
    );
    if (ok) ref.invalidate(hrIncentivesProvider);
  }
}

// ══════════════════════════ Staff setup ══════════════════════════

class _StaffSetupTab extends ConsumerWidget {
  const _StaffSetupTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ProviderList(
      provider: hrStaffProfilesProvider,
      emptyLabel: 'No staff found',
      emptyIcon: Icons.groups_rounded,
      tile: (context, row) {
        final user = (row['user'] is Map) ? (row['user'] as Map).cast<String, dynamic>() : <String, dynamic>{};
        return RecordCard(
          title: str(user['name'], 'Staff'),
          subtitle: '${str(row['work_mode'], 'wfo').toUpperCase()} · ${str(row['attendance_type'], 'manual')}'
              '${row['monthly_target'] != null ? ' · Target ${money(row['monthly_target'])}' : ''}',
          leadingIcon: Icons.person_rounded,
          trailing: IconButton(icon: const Icon(Icons.edit_rounded, size: 18), onPressed: () => _edit(context, ref, user, row)),
        );
      },
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, Rec user, Rec profile) async {
    final data = <String, dynamic>{};
    final ok = await showFormSheet(
      context,
      title: str(user['name'], 'Staff'),
      fields: (ctx) => [
        FSelect<String>(label: 'Attendance type', options: const ['manual', 'gps'],
            initial: str(profile['attendance_type'], 'manual'), onSaved: (v) => data['attendance_type'] = v),
        FSelect<String>(label: 'Work mode', options: const ['wfo', 'wfh', 'hybrid'],
            initial: str(profile['work_mode'], 'wfo'), onSaved: (v) => data['work_mode'] = v),
        FText(label: 'Duty start (HH:mm)', initial: profile['duty_start'] as String?, onSaved: (v) => v.isEmpty ? null : data['duty_start'] = v),
        FText(label: 'Duty end (HH:mm)', initial: profile['duty_end'] as String?, onSaved: (v) => v.isEmpty ? null : data['duty_end'] = v),
        FNumber(label: 'Monthly salary', initial: profile['monthly_salary'] as num?, onSaved: (v) => data['monthly_salary'] = v),
        FNumber(label: 'Monthly sales target', initial: profile['monthly_target'] as num?, onSaved: (v) => data['monthly_target'] = v),
      ],
      onSubmit: () => Api.put('/hr/staff-profiles/${user['id']}', data: data),
    );
    if (ok) ref.invalidate(hrStaffProfilesProvider);
  }
}

// ══════════════════════════ Break types / Leave types (generic CRUD) ══════════════════════════

class _BreakTypesTab extends ConsumerWidget {
  const _BreakTypesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ProviderList(
      provider: hrBreakTypesAdminProvider,
      emptyLabel: 'No break types configured',
      emptyIcon: Icons.free_breakfast_rounded,
      tile: (context, bt) => RecordCard(
        title: str(bt['name']),
        subtitle: '${bt['max_minutes'] != null ? '${bt['max_minutes']}m max' : 'No limit'}'
            '${bt['daily_limit'] != null ? ' · ${bt['daily_limit']}/day' : ''}${bt['is_paid'] == true ? ' · Paid' : ' · Unpaid'}',
        leadingIcon: Icons.free_breakfast_rounded,
        trailing: RowMenu(items: [
          ('Edit', Icons.edit_rounded, () => _editBreakType(context, existing: bt)),
          ('Delete', Icons.delete_outline_rounded, () async {
            final ok = await confirm(context, title: 'Delete "${bt['name']}"?', destructive: true, confirmLabel: 'Delete');
            if (!ok) return;
            final done = await runAction(context, () => Api.delete('/hr/break-types/${bt['id']}'), success: 'Deleted');
            if (done) ref.invalidate(hrBreakTypesAdminProvider);
          }),
        ]),
      ),
    );
  }
}

Future<void> _editBreakType(BuildContext context, {Rec? existing}) async {
  final data = <String, dynamic>{};
  final ok = await showFormSheet(
    context,
    title: existing == null ? 'Add break type' : 'Edit break type',
    fields: (ctx) => [
      FText(label: 'Name', initial: existing?['name'] as String?, required: true, onSaved: (v) => data['name'] = v),
      FNumber(label: 'Max minutes', initial: existing?['max_minutes'] as num?, onSaved: (v) => data['max_minutes'] = v),
      FNumber(label: 'Per day limit', initial: existing?['daily_limit'] as num?, onSaved: (v) => data['daily_limit'] = v),
    ],
    onSubmit: () => existing == null
        ? Api.post('/hr/break-types', data: data)
        : Api.patch('/hr/break-types/${existing['id']}', data: data),
  );
  if (ok && context.mounted) {
    ProviderScope.containerOf(context, listen: false).invalidate(hrBreakTypesAdminProvider);
  }
}

class _LeaveTypesTab extends ConsumerWidget {
  const _LeaveTypesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ProviderList(
      provider: hrLeaveTypesAdminProvider,
      emptyLabel: 'No leave types configured',
      emptyIcon: Icons.beach_access_rounded,
      tile: (context, lt) => RecordCard(
        title: str(lt['name']),
        subtitle: '${lt['max_days_per_year'] != null ? '${lt['max_days_per_year']} days/yr' : 'No limit'}'
            '${lt['requires_approval'] == true ? ' · Approval' : ' · Auto'}${lt['is_paid'] == true ? ' · Paid' : ' · Unpaid'}',
        leadingIcon: Icons.beach_access_rounded,
        trailing: RowMenu(items: [
          ('Edit', Icons.edit_rounded, () => _editLeaveType(context, existing: lt)),
          ('Delete', Icons.delete_outline_rounded, () async {
            final ok = await confirm(context, title: 'Delete "${lt['name']}"?', destructive: true, confirmLabel: 'Delete');
            if (!ok) return;
            final done = await runAction(context, () => Api.delete('/hr/leave-types/${lt['id']}'), success: 'Deleted');
            if (done) ref.invalidate(hrLeaveTypesAdminProvider);
          }),
        ]),
      ),
    );
  }
}

Future<void> _editLeaveType(BuildContext context, {Rec? existing}) async {
  final data = <String, dynamic>{};
  final ok = await showFormSheet(
    context,
    title: existing == null ? 'Add leave type' : 'Edit leave type',
    fields: (ctx) => [
      FText(label: 'Name', initial: existing?['name'] as String?, required: true, onSaved: (v) => data['name'] = v),
      FNumber(label: 'Max days/year', initial: existing?['max_days_per_year'] as num?, onSaved: (v) => data['max_days_per_year'] = v),
    ],
    onSubmit: () => existing == null
        ? Api.post('/hr/leave-types', data: data)
        : Api.patch('/hr/leave-types/${existing['id']}', data: data),
  );
  if (ok && context.mounted) {
    ProviderScope.containerOf(context, listen: false).invalidate(hrLeaveTypesAdminProvider);
  }
}

// ══════════════════════════ Office (settings) ══════════════════════════

class _OfficeTab extends ConsumerWidget {
  const _OfficeTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ProviderObject(
      provider: hrSettingsProvider,
      builder: (context, s) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          KvRow('Office hours', '${str(s['office_start'])} – ${str(s['office_end'])}'),
          KvRow('Geofence radius', '${s['geofence_radius_m'] ?? '—'} m'),
          KvRow('Geofence mandatory', s['geofence_mandatory'] == true ? 'Yes' : 'No'),
          KvRow('Late grace', '${s['grace_minutes'] ?? 0} min'),
          KvRow('Timezone', str(s['timezone'])),
          KvRow('Reopen requests', s['reopen_auto_approve'] == true ? 'Auto-approved' : 'Needs manager approval'),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => _editSettings(context, ref, s),
            icon: const Icon(Icons.edit_rounded),
            label: const Text('Edit office details'),
          ),
        ],
      ),
    );
  }

  Future<void> _editSettings(BuildContext context, WidgetRef ref, Rec s) async {
    final data = <String, dynamic>{};
    final ok = await showFormSheet(
      context,
      title: 'Office details',
      fields: (ctx) => [
        FText(label: 'Office start (HH:mm)', initial: (s['office_start'] as String?)?.substring(0, 5), onSaved: (v) => v.isEmpty ? null : data['office_start'] = v),
        FText(label: 'Office end (HH:mm)', initial: (s['office_end'] as String?)?.substring(0, 5), onSaved: (v) => v.isEmpty ? null : data['office_end'] = v),
        FNumber(label: 'Geofence radius (m)', initial: s['geofence_radius_m'] as num?, onSaved: (v) => data['geofence_radius_m'] = v),
        FNumber(label: 'Late grace (minutes)', initial: s['grace_minutes'] as num?, onSaved: (v) => data['grace_minutes'] = v),
        FText(label: 'Timezone', initial: s['timezone'] as String?, onSaved: (v) => v.isEmpty ? null : data['timezone'] = v),
        FBoolField(
          label: 'Auto-approve reopen requests',
          hint: "Off: a manager must approve each \"accidentally clocked out\" request. On: it's granted instantly.",
          initial: s['reopen_auto_approve'] == true,
          onSaved: (v) => data['reopen_auto_approve'] = v,
        ),
      ],
      onSubmit: () => Api.put('/hr/settings', data: data),
    );
    if (ok) ref.invalidate(hrSettingsProvider);
  }
}
