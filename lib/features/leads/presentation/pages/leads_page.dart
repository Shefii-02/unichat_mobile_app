import 'dart:async';
import 'package:dio/dio.dart';
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
import 'package:unichat_mobile_app/features/leads/presentation/widgets/lead_contact_fields.dart';
import 'package:unichat_mobile_app/features/leads/presentation/widgets/lead_form_fields.dart';
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
  int _seq = 0;               // numbers each request, so a slow older answer never overwrites a newer one
  String? _error;             // why the last load failed (shown with a Retry button instead of a silent empty list)
  bool? _tabActive;           // whether this tab is the one on screen (the bottom-nav tabs stay alive underneath)
  bool _onlyStarred = false;   // show only the leads I starred
  int _page = 1;
  bool _hasMore = true;
  final _searchCtrl = TextEditingController();
  ProviderSubscription<String?>? _wsSub;
  Map<String, int> _counts = const {}; // stage → leads
  int _missed = 0; // follow-ups past their time

  @override
  void initState() {
    super.initState();
    _load(reset: true);
    _loadCounts();
    // the tab stays alive when the workspace is switched on Home, so reload with the new scope
    _wsSub = ProviderScope.containerOf(context, listen: false).listen<String?>(
      activeWorkspaceProvider,
      (_, __) {
        _load(reset: true);
        _loadCounts();
      },
    );
  }

  /// Stage counts (GET /leads/dashboard) and missed follow-ups (GET /tasks/dashboard) for the status tiles. Best effort — tiles show "—" if either fails.
  Future<void> _loadCounts() async {
    try {
      final d = await Api.one('/leads/dashboard');
      final lists = (d['lists'] as List?) ?? const [];
      final byStage = lists.whereType<Map>().firstWhere(
        (l) => '${l['title']}'.toLowerCase() == 'by stage',
        orElse: () => const {},
      );
      final counts = <String, int>{};
      for (final r
          in (byStage['rows'] as List? ?? const []).whereType<List>()) {
        if (r.length > 1)
          counts['${r[0]}'
                  .toLowerCase()
                  .replaceAll(' ', '_')
                  .replaceAll('-', '_')] =
              (r[1] as num).toInt();
      }
      if (mounted) setState(() => _counts = counts);
    } catch (_) {}
    try {
      final t = await Api.one('/tasks/dashboard');
      final k = ((t['kpis'] as List?) ?? const []).whereType<Map>().firstWhere(
        (e) => '${e['label']}'.toLowerCase() == 'overdue',
        orElse: () => const {},
      );
      if (mounted) setState(() => _missed = (k['value'] as num?)?.toInt() ?? 0);
    } catch (_) {}
  }

  // The Leads tab lives on in the bottom bar after it was built. When it comes back on screen (e.g. tapping "My leads" on Home), reload so
  // it never shows a list that was empty or stale from before.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final active = TickerMode.valuesOf(context).enabled;
    if (_tabActive == false && active) {
      _load(reset: true);
      _loadCounts();
    }
    _tabActive = active;
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
    final mine = ++_seq;
    setState(() { _loading = true; _error = null; });
    try {
      // In the Sales workspace the list is only the leads assigned to this person
      final box = ProviderScope.containerOf(context);
      final myId =
          box.read(activeWorkspaceProvider) == 'sales'
              ? box.read(authProvider).value?.id
              : null;
      final params = {
        'page': _page,
        if (myId != null) 'assigned_to': myId,
        if (widget.source != null) 'source': widget.source,
        if (_stage != null) 'stage': _stage,
        if (_onlyStarred) 'starred': 1,
        if (_searchCtrl.text.trim().isNotEmpty)
          'search': _searchCtrl.text.trim(),
      };
      final res = await DioClient.laravelDio.get(
        '/leads',
        queryParameters: params,
      );
      if (!mounted || mine != _seq) return;   // a newer request has started — this answer is out of date
      final data = res.data as Map<String, dynamic>;
      final items = (data['data'] as List?) ?? [];
      setState(() {
        _leads = reset ? items : [..._leads, ...items];
        _hasMore = items.isNotEmpty;
        _loading = false;
      });
    } catch (e) {
      if (mounted && mine == _seq) setState(() { _loading = false; _error = apiErrorMessage(e); });
    }
  }

  Future<void> _createLead() async {
    if (await showNewLeadSheet(context)) _load(reset: true);
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
          child: Text(
            "You don't have access to this section",
            style: TextStyle(color: context.mutedColor),
          ),
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
                  Text(
                    widget.title ?? 'Leads',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.search_rounded,
                          size: 18,
                          color: M.heroMuted,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _searchCtrl,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                            ),
                            decoration: const InputDecoration(
                              hintText: 'Search leads by name or phone',
                              hintStyle: TextStyle(
                                color: M.heroMuted,
                                fontSize: 13,
                              ),
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(
                                vertical: 10,
                              ),
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
              child:
                  _loading && _leads.isEmpty
                      ? const Center(child: CircularProgressIndicator())
                      : _leads.isEmpty && _error != null
                      ? Center(
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: context.mutedColor)),
                          const SizedBox(height: 8),
                          TextButton(onPressed: () => _load(reset: true), child: const Text('Retry')),
                        ]),
                      )
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
    Widget tile(
      String label,
      int? n,
      Tint t,
      VoidCallback onTap, {
      bool selected = false,
    }) => Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: t.$1,
            borderRadius: BorderRadius.circular(12),
            border: selected ? Border.all(color: t.$2, width: 1.5) : null,
          ),
          child: Column(
            children: [
              Text(
                n == null ? '—' : '$n',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: t.$2,
                ),
              ),
              Text(label, style: TextStyle(fontSize: 10, color: t.$3)),
            ],
          ),
        ),
      ),
    );
    void pick(String? stage) {
      setState(() => _stage = stage);
      _load(reset: true);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          tile(
            'New',
            _counts['new'],
            tintPeach,
            () => pick('new'),
            selected: _stage == 'new',
          ),
          const SizedBox(width: 8),
          tile(
            'Follow-up',
            _counts['follow_up'],
            tintAmber,
            () => pick('follow_up'),
            selected: _stage == 'follow_up',
          ),
          const SizedBox(width: 8),
          tile(
            'Missed',
            _missed,
            tintRed,
            () => context.push('/crm-followups'),
          ),
          const SizedBox(width: 8),
          tile(
            'Closed',
            _counts['enrolled'],
            tintGreen,
            () => pick('enrolled'),
            selected: _stage == 'enrolled',
          ),
        ],
      ),
    );
  }

  /// "Contact now": one tap opens Call / WhatsApp for the lead.
  void _contactNow(String name, String phone) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder:
          (ctx) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: Text(
                    name,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(phone),
                ),
                ListTile(
                  leading: const Icon(Icons.call_rounded, color: Colors.green),
                  title: const Text('Call'),
                  onTap: () {
                    Navigator.pop(ctx);
                    launchUrl(Uri.parse('tel:$phone'));
                  },
                ),
                ListTile(
                  leading: const Icon(
                    Icons.message_rounded,
                    color: Colors.green,
                  ),
                  title: const Text('WhatsApp'),
                  onTap: () {
                    Navigator.pop(ctx);
                    launchUrl(
                      Uri.parse(
                        'https://wa.me/${phone.replaceAll(RegExp(r'[^0-9]'), '')}',
                      ),
                      mode: LaunchMode.externalApplication,
                    );
                  },
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
        itemCount: _stageFilters.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          if (i == 0) {
            return FilterChip(
              avatar: Icon(_onlyStarred ? Icons.star_rounded : Icons.star_outline_rounded, size: 16, color: _onlyStarred ? const Color(0xFFF59E0B) : context.mutedColor),
              label: const Text('Starred'),
              selected: _onlyStarred,
              onSelected: (v) {
                setState(() => _onlyStarred = v);
                _load(reset: true);
              },
              showCheckmark: false,
              backgroundColor: Colors.transparent,
              selectedColor: Colors.transparent,
              side: BorderSide(color: _onlyStarred ? const Color(0xFFF59E0B) : context.lineColor, width: _onlyStarred ? 1.6 : 1),
              labelStyle: TextStyle(color: _onlyStarred ? const Color(0xFF92400E) : context.mutedColor, fontSize: 11.5, fontWeight: _onlyStarred ? FontWeight.w700 : FontWeight.w500),
            );
          }
          final f = _stageFilters[i - 1];
          final sel = _stage == f.$2;
          final theme = Theme.of(context);
          return ChoiceChip(
            label: Text(f.$1),
            selected: sel,
            onSelected: (_) {
              setState(() => _stage = f.$2);
              _load(reset: true);
            },
            showCheckmark: false,
            selectedColor: Colors.transparent,        // the chosen tab is marked by its border, not a filled background
            backgroundColor: Colors.transparent,
            side: BorderSide(color: sel ? theme.colorScheme.onSurface : context.lineColor, width: sel ? 1.6 : 1),
            labelStyle: TextStyle(
              color: sel ? theme.colorScheme.onSurface : context.mutedColor,
              fontSize: 11.5,
              fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
            ),
          );
        },
      ),
    );
  }

  /// "12 Nov" style short date from an ISO string.
  String _day(Object? iso) {
    final d = DateTime.tryParse('$iso')?.toLocal();
    if (d == null) return '—';
    const m = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${d.day} ${m[d.month - 1]}';
  }

  /// Star / unstar a lead for myself: the star flips at once and is put back if the server refuses.
  Future<void> _toggleStar(Map<String, dynamic> lead) async {
    final next = lead['starred'] != true;
    setState(() => lead['starred'] = next);
    try {
      await Api.put('/leads/${lead['id']}/star', data: {'starred': next});
      if (!next && _onlyStarred && mounted) setState(() => _leads.removeWhere((l) => l is Map && l['id'] == lead['id']));
    } catch (e) {
      if (!mounted) return;
      setState(() => lead['starred'] = !next);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
    }
  }

  Widget _leadRow(Map<String, dynamic> lead) {
    final contact = lead['contact'] as Map<String, dynamic>?;
    final name = contact?['name'] as String? ?? 'Unknown';
    final phone = contact?['phone'] as String? ?? '';
    final stage = lead['stage'] as String? ?? 'new';
    final source = lead['source'] as String? ?? '';
    final tint = stageTint[stage] ?? tintPeach;
    final initials =
        name.trim().isEmpty
            ? '?'
            : name
                .trim()
                .split(' ')
                .where((w) => w.isNotEmpty)
                .map((w) => w[0].toUpperCase())
                .take(2)
                .join();

    return InkWell(
      onTap: () => context.push('/lead-detail/${lead['id']}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            InkResponse(
              onTap: () => _toggleStar(lead),
              radius: 20,
              child: Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Icon(
                  lead['starred'] == true ? Icons.star_rounded : Icons.star_outline_rounded,
                  size: 24,
                  color: lead['starred'] == true ? const Color(0xFFF59E0B) : context.mutedColor,
                ),
              ),
            ),
            CircleAvatar(
              radius: 20,
              backgroundColor: tint.$1,
              child: Text(
                initials,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: tint.$2,
                ),
              ),
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
                        style: TextStyle(
                          fontSize: 10.5,
                          color: context.mutedColor,
                        ),
                      ),
                    ),
                  if (source.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        source,
                        style: TextStyle(
                          fontSize: 11,
                          color: context.mutedColor,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: tint.$1,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    stageLabel(stage),
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: tint.$2,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                if (phone.isNotEmpty)
                  GestureDetector(
                    onTap: () => _contactNow(name, phone),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: M.taskDoneBg,
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.call_rounded,
                            size: 12,
                            color: Colors.white,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'Contact now',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
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

/// "New lead" form as a tall sheet — used by the Leads tab and the Sales dashboard's quick action. True when a lead was created.
Future<bool> showNewLeadSheet(BuildContext context) async {
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
  if (!context.mounted) return false;
  final myId = ProviderScope.containerOf(context, listen: false).read(authProvider).value?.id;   // read before any await below
  final data = <String, dynamic>{};
  final who = LeadContactState();
  final form = LeadFormState();
  bool addToMine = true;   // new leads go to "My leads" unless another staff member is picked
  int? openLeadId;   // set when the customer already has an open lead and the staff chose to go to it
  final ok = await showFormSheet(
    context,
    title: 'New lead',
    submitLabel: 'Create',
    fields:
        (ctx) => [
          LeadContactFields(state: who),
          LeadOriginField(
            state: form,
          ), // first: which number / account / campaign it came from
          LeadItemField(state: form),
          LeadCategoriesField(state: form),
          FRadio<String>(
            label: 'Priority',
            options: const ['low', 'medium', 'high'],
            initial: 'medium',
            onSaved: (v) => data['priority'] = v ?? 'medium',
          ),
          StatefulBuilder(
            builder: (_, setS) => CheckboxListTile(
              value: addToMine,
              onChanged: (v) => setS(() => addToMine = v ?? true),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('Add to my leads', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
              subtitle: const Text('Assigned to you — it appears under My leads. Picking another staff member below overrides this.', style: TextStyle(fontSize: 11.5)),
            ),
          ),
          if (staff.isNotEmpty)
            FSelect<Map<String, dynamic>>(
              label: 'Assign to (optional)',
              options: staff,
              labelOf: (s) => '${s['name']}',
              onSaved:
                  (s) =>
                      s?['id'] != null ? data['assigned_to'] = s!['id'] : null,
            ),
          FText(
            label: 'Notes',
            maxLines: 3,
            onSaved: (v) => v.isEmpty ? null : data['notes'] = v,
          ),
        ],
    onSubmit: () async {
      if (!who.ready) throw Exception('Wait for the number check to finish.');
      data['contact_id'] = await who.save();
      data.addAll(form.originData());
      if (form.categories.isNotEmpty) data['categories'] = form.categories;
      if (form.itemId != null) data['listing_id'] = form.itemId;
      // "Add to my leads": assign to me unless another staff member was chosen
      if (addToMine && data['assigned_to'] == null && myId != null) data['assigned_to'] = myId;
      try {
        await Api.post('/leads', data: data);
      } on DioException catch (e) {
        final body = e.response?.data;
        final existing = body is Map && body['error_code'] == 'duplicate_lead' ? body['existing_lead'] : null;
        if (existing is! Map || !context.mounted) rethrow;
        // the customer already has an open lead: tell who owns it, let staff note what the customer needs, and ask whether to open it
        final choice = await _askOpenExistingLead(context, Map<String, dynamic>.from(existing),
            customer: who.name.text.trim().isEmpty ? who.phone.text.trim() : who.name.text.trim(), defaultNote: '${data['notes'] ?? ''}');
        if (choice == null) rethrow;      // "No": stay on the form with the usual message
        openLeadId = choice;
      }
    },
  );
  if (ok && openLeadId != null && context.mounted) context.push('/lead-detail/$openLeadId');
  // The sheet is still sliding out (and its fields still reading these controllers) the moment the future completes —
  // disposing right now crashes the closing animation. Let it finish first.
  Future.delayed(const Duration(milliseconds: 500), () {
    who.dispose();
    form.dispose();
  });
  return ok;
}


/// "This customer already has an open lead": who owns it, a warning when it isn't the user's, a note box for what the customer needs now
/// (saved as an activity on that lead) and "Open that lead?". Returns the lead id when the user says Yes, null for No.
Future<int?> _askOpenExistingLead(BuildContext context, Map<String, dynamic> lead, {required String customer, String defaultNote = ''}) {
  final id = (lead['id'] as num).toInt();
  final owner = lead['assigned_to'] is Map ? '${(lead['assigned_to'] as Map)['name']}' : null;
  final mine = lead['mine'] == true, canView = lead['can_view'] != false, claimable = lead['claimable'] == true;
  final note = TextEditingController(text: defaultNote);
  bool saving = false, saved = false, taken = false, opening = false;   // taken: an unowned lead has been assigned to me
  return showDialog<int?>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
      // nobody owns it yet → assign it to me first (needed to open it or write on it), once
      Future<void> claimIfUnowned() async {
        if (claimable && !taken) {
          await Api.post('/leads/$id/claim');
          taken = true;
        }
      }

      Future<void> openIt() async {
        setS(() => opening = true);
        try {
          await claimIfUnowned();
          if (ctx.mounted) Navigator.pop(ctx, id);
        } catch (e) {
          setS(() => opening = false);
          if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
        }
      }

      Future<void> saveNote() async {
        if (note.text.trim().isEmpty) return;
        setS(() => saving = true);
        try {
          await claimIfUnowned();
          await Api.post('/leads/$id/notes', data: {'content': 'New enquiry: ${note.text.trim()}'});
          setS(() { saved = true; saving = false; });
        } catch (e) {
          setS(() => saving = false);
          if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
        }
      }

      return AlertDialog(
        title: const Text('Already an open lead'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(customer.isEmpty ? 'This customer' : customer, style: const TextStyle(fontWeight: FontWeight.w700)),
            Text('Stage: ${'${lead['stage']}'.replaceAll('_', ' ')}${lead['item'] != null ? ' · Product / service: ${lead['item']}' : ''} · Assigned to: ${owner ?? 'nobody yet'}${mine ? ' (you)' : ''}', style: const TextStyle(fontSize: 12.5)),
            const SizedBox(height: 10),
            if (!canView)
              _dupNotice('This lead belongs to ${owner ?? 'another staff member'} and you can\'t open it. Ask them or a team head to add this enquiry.', const Color(0xFFDC2626))
            else if (claimable && !taken)
              _dupNotice('This lead has no owner yet. Opening it (or saving a note on it) assigns it to you.', const Color(0xFF2563EB))
            else if (!mine && !taken)
              _dupNotice('This lead is not assigned to you${owner != null ? ' — it belongs to $owner' : ' — it has no owner yet'}. You can still open it and add what the customer needs.', const Color(0xFFD97706)),
            if (canView) ...[
              const SizedBox(height: 10),
              const Text('What does the customer need now?', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 6),
              TextField(controller: note, maxLines: 3, onChanged: (_) => setS(() => saved = false), decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'Saved as an activity on that lead')),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(onPressed: saving || saved || note.text.trim().isEmpty ? null : saveNote, child: Text(saved ? '✓ Saved to that lead' : saving ? 'Saving…' : 'Save to that lead')),
              ),
            ],
            const SizedBox(height: 4),
            const Text('Open that lead?', style: TextStyle(fontWeight: FontWeight.w700)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text('No')),
          FilledButton(onPressed: canView && !opening ? openIt : null, child: Text(opening ? 'Opening…' : (claimable && !taken ? 'Yes, open & assign to me' : 'Yes, open lead'))),
        ],
      );
    }),
  ).whenComplete(() {
    // the dialog is still sliding out (its note field still reads this controller) — dispose after it has gone
    Future.delayed(const Duration(milliseconds: 500), note.dispose);
  });
}

Widget _dupNotice(String text, Color c) => Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10), border: Border.all(color: c.withValues(alpha: 0.35))),
      child: Text('⚠ $text', style: TextStyle(fontSize: 12.5, color: c)),
    );
