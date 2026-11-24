import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:unichat_mobile_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:unichat_mobile_app/features/workspace/workspace_provider.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:unichat_mobile_app/core/network/dio_client.dart';
import 'package:unichat_mobile_app/core/theme/mockup_palette.dart';
import 'package:unichat_mobile_app/core/widgets/app_empty_state.dart';
import 'package:unichat_mobile_app/core/permissions/permission_guard.dart';
import 'package:unichat_mobile_app/features/leads/lead_stage.dart';
import 'package:unichat_mobile_app/features/modules/_shared.dart';

/// Lead pipeline list: All/New/Contacted/Won (Lead.stage) with search-by-name/phone, quick
/// call/message actions, and a FAB to add a lead. Backed by `GET /leads`
/// (LeadController::index — stage/search/per_page params; auto-scoped to the caller's own
/// leads unless they hold `leads.view_all`).
class LeadsPage extends StatefulWidget {
  const LeadsPage({super.key, this.source, this.title});
  /// Only leads from this source (Lead sources → tap a source)
  final String? source;
  final String? title;
  @override
  State<LeadsPage> createState() => _LeadsPageState();
}

const _stageFilters = <(String label, String? stage)>[
  ('All', null),
  ('New', 'new'),
  ('Contacted', 'contacted'),
  ('Follow-up', 'follow_up'),
  ('Won', 'enrolled'),
];

class _LeadsPageState extends State<LeadsPage> {
  List<dynamic> _leads = [];
  bool _loading = true;
  String? _stage;
  int _page = 1;
  bool _hasMore = true;
  final _searchCtrl = TextEditingController();
  ProviderSubscription<String?>? _wsSub;
  Map<String, int> _counts = const {};   // stage → leads
  int _missed = 0;                       // follow-ups past their time

  @override
  void initState() {
    super.initState();
    _load();
    _loadCounts();
    // the tab stays alive when the workspace is switched on Home, so reload with the new scope
    _wsSub = ProviderScope.containerOf(context, listen: false).listen<String?>(activeWorkspaceProvider, (_, __) {
      _load(reset: true);
      _loadCounts();
    });
  }

  /// Stage counts (GET /leads/dashboard) and missed follow-ups (GET /tasks/dashboard) for the status tiles. Best effort — tiles show "—" if either fails.
  Future<void> _loadCounts() async {
    try {
      final d = await Api.one('/leads/dashboard');
      final lists = (d['lists'] as List?) ?? const [];
      final byStage = lists.whereType<Map>().firstWhere((l) => '${l['title']}'.toLowerCase() == 'by stage', orElse: () => const {});
      final counts = <String, int>{};
      for (final r in (byStage['rows'] as List? ?? const []).whereType<List>()) {
        if (r.length > 1) counts['${r[0]}'.toLowerCase().replaceAll(' ', '_').replaceAll('-', '_')] = (r[1] as num).toInt();
      }
      if (mounted) setState(() => _counts = counts);
    } catch (_) {}
    try {
      final t = await Api.one('/tasks/dashboard');
      final k = ((t['kpis'] as List?) ?? const []).whereType<Map>().firstWhere((e) => '${e['label']}'.toLowerCase() == 'overdue', orElse: () => const {});
      if (mounted) setState(() => _missed = (k['value'] as num?)?.toInt() ?? 0);
    } catch (_) {}
  }

  @override
  void dispose() {
    _wsSub?.close();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load({bool reset = false}) async {
    if (reset) {
      _page = 1;
      _leads = [];
    }
    setState(() => _loading = true);
    try {
      // In the Sales workspace the list is only the leads assigned to this person
      final box = ProviderScope.containerOf(context);
      final myId = box.read(activeWorkspaceProvider) == 'sales' ? box.read(authProvider).value?.id : null;
      final params = {
        'page': _page,
        if (myId != null) 'assigned_to': myId,
        if (widget.source != null) 'source': widget.source,
        if (_stage != null) 'stage': _stage,
        if (_searchCtrl.text.trim().isNotEmpty) 'search': _searchCtrl.text.trim(),
      };
      final res = await DioClient.laravelDio.get('/leads', queryParameters: params);
      final data = res.data as Map<String, dynamic>;
      final items = (data['data'] as List?) ?? [];
      setState(() {
        _leads = reset ? items : [..._leads, ...items];
        _hasMore = items.isNotEmpty;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _createLead() async {
    List<Map<String, dynamic>> contacts;
    try {
      contacts = await Api.list('/contacts', query: {'per_page': 100});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
      }
      return;
    }
    if (!mounted || contacts.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Add a contact first.')));
      }
      return;
    }
    // Full staff roster was fetched here regardless of staff.view — the "Assign to" field
    // below already tolerates an empty list, so gating the fetch just omits that field.
    List<Map<String, dynamic>> staff = const [];
    if (PermissionGuard.can('staff.view')) {
      try {
        staff = await Api.list('/staff');
      } catch (_) {
        staff = const [];
      }
    }
    if (!mounted) return;
    final data = <String, dynamic>{};
    final ok = await showFormSheet(
      context,
      title: 'New lead',
      submitLabel: 'Create',
      fields: (ctx) => [
        FSelect<Map<String, dynamic>>(
          label: 'Contact',
          options: contacts,
          labelOf: (c) => '${c['name'] ?? c['phone']} · ${c['phone'] ?? ''}',
          onSaved: (c) => data['contact_id'] = c?['id'],
        ),
        FSelect<String>(
          label: 'Priority',
          options: const ['low', 'medium', 'high'],
          initial: 'medium',
          onSaved: (v) => data['priority'] = v ?? 'medium',
        ),
        FText(
          label: 'Category',
          onSaved: (v) => v.isEmpty ? null : data['category'] = v,
        ),
        if (staff.isNotEmpty)
          FSelect<Map<String, dynamic>>(
            label: 'Assign to (optional)',
            options: staff,
            labelOf: (s) => '${s['name']}',
            onSaved: (s) => s?['id'] != null ? data['assigned_to'] = s!['id'] : null,
          ),
        FText(
          label: 'Notes',
          maxLines: 3,
          onSaved: (v) => v.isEmpty ? null : data['notes'] = v,
        ),
      ],
      onSubmit: () => Api.post('/leads', data: data),
    );
    if (ok) _load(reset: true);
  }

  @override
  Widget build(BuildContext context) {
    // The bottom-nav tab bypasses the module catalogue's own permission gating entirely (it's
    // hardcoded in MainShell, not driven by AppModules) — self-check here so a role without
    // leads access can't reach it just by tapping the tab.
    if (!PermissionGuard.can('leads.view')) {
      return Scaffold(
        appBar: AppBar(title: const Text('Leads')),
        body: Center(
          child: Text("You don't have access to this section",
              style: TextStyle(color: context.mutedColor)),
        ),
      );
    }

    return Scaffold(
      floatingActionButton: FloatingActionButton(
        backgroundColor: M.lavenderMuted,
        onPressed: _createLead,
        child: const Icon(Icons.add_rounded),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              color: M.heroBg,
              padding: const EdgeInsets.fromLTRB(20, 10, 18, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.title ?? 'Leads', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Colors.white)),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                    child: Row(
                      children: [
                        const Icon(Icons.search_rounded, size: 18, color: M.heroMuted),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _searchCtrl,
                            style: const TextStyle(color: Colors.white, fontSize: 13),
                            decoration: const InputDecoration(
                              hintText: 'Search leads by name or phone',
                              hintStyle: TextStyle(color: M.heroMuted, fontSize: 13),
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(vertical: 10),
                            ),
                            textInputAction: TextInputAction.search,
                            onSubmitted: (_) => _load(reset: true),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            _statusTiles(),
            _filterChips(),
            Expanded(
              child: _loading && _leads.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : _leads.isEmpty
                      ? AppEmptyState(
                          icon: Icons.people_outline,
                          title: 'No leads',
                          subtitle: 'No leads found for this filter.',
                        )
                      : RefreshIndicator(
                          onRefresh: () async {
                            await _load(reset: true);
                            unawaited(_loadCounts());
                          },
                          child: ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: _leads.length + (_hasMore ? 1 : 0),
                            itemBuilder: (_, i) {
                              if (i == _leads.length) {
                                return Center(
                                  child: TextButton(
                                    onPressed: () {
                                      _page++;
                                      _load();
                                    },
                                    child: const Text('Load more'),
                                  ),
                                );
                              }
                              return _leadRow(_leads[i]);
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  /// Lead status tiles — New / Follow-up / Missed / Closed — each a shortcut to that filter (Missed opens the follow-ups list).
  Widget _statusTiles() {
    Widget tile(String label, int? n, Tint t, VoidCallback onTap, {bool selected = false}) => Expanded(
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 9),
              decoration: BoxDecoration(color: t.$1, borderRadius: BorderRadius.circular(12), border: selected ? Border.all(color: t.$2, width: 1.5) : null),
              child: Column(children: [
                Text(n == null ? '—' : '$n', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: t.$2)),
                Text(label, style: TextStyle(fontSize: 10, color: t.$3)),
              ]),
            ),
          ),
        );
    void pick(String? stage) {
      setState(() => _stage = stage);
      _load(reset: true);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(children: [
        tile('New', _counts['new'], tintPeach, () => pick('new'), selected: _stage == 'new'),
        const SizedBox(width: 8),
        tile('Follow-up', _counts['follow_up'], tintAmber, () => pick('follow_up'), selected: _stage == 'follow_up'),
        const SizedBox(width: 8),
        tile('Missed', _missed, tintRed, () => context.push('/crm-followups')),
        const SizedBox(width: 8),
        tile('Closed', _counts['enrolled'], tintGreen, () => pick('enrolled'), selected: _stage == 'enrolled'),
      ]),
    );
  }

  /// "Contact now": one tap opens Call / WhatsApp for the lead.
  void _contactNow(String name, String phone) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(title: Text(name, style: const TextStyle(fontWeight: FontWeight.w700)), subtitle: Text(phone)),
          ListTile(
            leading: const Icon(Icons.call_rounded, color: Colors.green),
            title: const Text('Call'),
            onTap: () { Navigator.pop(ctx); launchUrl(Uri.parse('tel:$phone')); },
          ),
          ListTile(
            leading: const Icon(Icons.message_rounded, color: Colors.green),
            title: const Text('WhatsApp'),
            onTap: () { Navigator.pop(ctx); launchUrl(Uri.parse('https://wa.me/${phone.replaceAll(RegExp(r'[^0-9]'), '')}'), mode: LaunchMode.externalApplication); },
          ),
        ]),
      ),
    );
  }

  Widget _filterChips() {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        scrollDirection: Axis.horizontal,
        itemCount: _stageFilters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final f = _stageFilters[i];
          final sel = _stage == f.$2;
          final theme = Theme.of(context);
          return ChoiceChip(
            label: Text(f.$1),
            selected: sel,
            onSelected: (_) {
              setState(() => _stage = f.$2);
              _load(reset: true);
            },
            selectedColor: theme.colorScheme.onSurface,
            backgroundColor: context.altSurface,
            side: BorderSide.none,
            labelStyle: TextStyle(
                color: sel ? theme.colorScheme.surface : context.mutedColor,
                fontSize: 11.5,
                fontWeight: FontWeight.w500),
          );
        },
      ),
    );
  }

  /// "12 Nov" style short date from an ISO string.
  String _day(Object? iso) {
    final d = DateTime.tryParse('$iso')?.toLocal();
    if (d == null) return '—';
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${d.day} ${m[d.month - 1]}';
  }

  Widget _leadRow(Map<String, dynamic> lead) {
    final contact = lead['contact'] as Map<String, dynamic>?;
    final name = contact?['name'] as String? ?? 'Unknown';
    final phone = contact?['phone'] as String? ?? '';
    final stage = lead['stage'] as String? ?? 'new';
    final source = lead['source'] as String? ?? '';
    final tint = stageTint[stage] ?? tintPeach;
    final initials = name.trim().isEmpty
        ? '?'
        : name.trim().split(' ').where((w) => w.isNotEmpty).map((w) => w[0].toUpperCase()).take(2).join();

    return InkWell(
      onTap: () => context.push('/lead-detail/${lead['id']}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: tint.$1,
              child: Text(initials, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: tint.$2)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: const TextStyle(fontSize: 13.5)),
                  if (lead['created_at'] != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        'Created ${_day(lead['created_at'])}${lead['last_activity_at'] != null ? ' · Active ${_day(lead['last_activity_at'])}' : ''}',
                        style: TextStyle(fontSize: 10.5, color: context.mutedColor),
                      ),
                    ),
                  if (source.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(source, style: TextStyle(fontSize: 11, color: context.mutedColor)),
                    ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: tint.$1, borderRadius: BorderRadius.circular(8)),
                  child: Text(stageLabel(stage),
                      style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: tint.$2)),
                ),
                const SizedBox(height: 6),
                if (phone.isNotEmpty)
                  GestureDetector(
                    onTap: () => _contactNow(name, phone),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: M.taskDoneBg, borderRadius: BorderRadius.circular(99)),
                      child: const Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.call_rounded, size: 12, color: Colors.white),
                        SizedBox(width: 4),
                        Text('Contact now', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: Colors.white)),
                      ]),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
