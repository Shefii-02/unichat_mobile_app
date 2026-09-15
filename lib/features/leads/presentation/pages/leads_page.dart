import 'package:flutter/material.dart';
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
  const LeadsPage({super.key});
  @override
  State<LeadsPage> createState() => _LeadsPageState();
}

const _stageFilters = <(String label, String? stage)>[
  ('All', null),
  ('New', 'new'),
  ('Contacted', 'contacted'),
  ('Won', 'enrolled'),
];

class _LeadsPageState extends State<LeadsPage> {
  List<dynamic> _leads = [];
  bool _loading = true;
  String? _stage;
  int _page = 1;
  bool _hasMore = true;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
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
      final params = {
        'page': _page,
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
                  const Text('Leads', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Colors.white)),
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
                          onRefresh: () => _load(reset: true),
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
      onTap: () => context.push('/leads/${lead['id']}'),
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
                Row(
                  children: [
                    if (phone.isNotEmpty) ...[
                      GestureDetector(
                        onTap: () => launchUrl(Uri.parse('tel:$phone')),
                        child: Icon(Icons.call_rounded, size: 15, color: Theme.of(context).colorScheme.primary),
                      ),
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: () => launchUrl(
                            Uri.parse('https://wa.me/${phone.replaceAll(RegExp(r'[^0-9]'), '')}')),
                        child: Icon(Icons.message_rounded, size: 15, color: Theme.of(context).colorScheme.primary),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
