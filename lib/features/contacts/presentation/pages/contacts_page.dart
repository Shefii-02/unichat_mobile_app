import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:unichat_mobile_app/core/constants/app_colors.dart';
import 'package:unichat_mobile_app/core/network/dio_client.dart';
import 'package:unichat_mobile_app/core/utils/format_utils.dart';
import 'package:unichat_mobile_app/core/widgets/app_avatar.dart';
import 'package:unichat_mobile_app/core/widgets/app_empty_state.dart';
import 'package:unichat_mobile_app/core/widgets/lead_score_badge.dart';
import 'package:unichat_mobile_app/core/permissions/permission_guard.dart';
import 'package:unichat_mobile_app/features/modules/_shared.dart';

class ContactsPage extends StatefulWidget {
  const ContactsPage({super.key});
  @override
  State<ContactsPage> createState() => _ContactsPageState();
}

class _ContactsPageState extends State<ContactsPage> {
  List<dynamic> _contacts = [];
  bool _loading = true;
  final _searchCtrl = TextEditingController();
  String _search = '';
  String _view = 'all';            // all | named | unsaved
  String? _letter;                 // A–Z, or '#'
  int? _labelId;
  DateTimeRange? _created;
  bool _az = false;                // sort A → Z instead of newest first
  List<Map<String, dynamic>> _labels = [];

  @override
  void initState() {
    super.initState();
    _load();
    DioClient.laravelDio.get('/labels').then((r) {
      final d = r.data;
      final rows = (d is Map ? (d['data'] ?? d['labels']) : d) as List? ?? const [];
      if (mounted) setState(() => _labels = rows.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList());
    }).catchError((_) {});
    _searchCtrl.addListener(() {
      setState(() => _search = _searchCtrl.text);
      _load();
    });
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await DioClient.laravelDio.get('/contacts', queryParameters: {
        if (_search.isNotEmpty) 'search': _search,
        if (_view == 'unsaved') 'unnamed': 1,
        if (_view == 'named') 'named': 1,
        if (_letter != null) 'letter': _letter,
        if (_labelId != null) 'label_id': _labelId,
        if (_created != null) 'created_from': _created!.start.toIso8601String().substring(0, 10),
        if (_created != null) 'created_to': _created!.end.toIso8601String().substring(0, 10),
        'sort_by': _az || _letter != null ? 'name' : 'created_at',
        'sort_dir': _az || _letter != null ? 'asc' : 'desc',
        'per_page': 100,
      });
      final data = res.data as Map<String, dynamic>;
      if (mounted) setState(() { _contacts = (data['data'] as List?) ?? []; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() { _searchCtrl.dispose(); super.dispose(); }

  Future<void> _createContact() async {
    if (await showNewContactSheet(context)) _load();
  }

  void _set(VoidCallback f) {
    setState(f);
    _load();
  }

  /// Saved / unsaved numbers, label, created-date range and A–Z — one scrollable strip, then the letter bar.
  Widget _filters(BuildContext context) {
    Widget chip(String label, bool on, VoidCallback tap, {IconData? icon}) => Padding(
          padding: const EdgeInsets.only(right: 6),
          child: FilterChip(label: Text(label), avatar: icon == null ? null : Icon(icon, size: 16), selected: on, onSelected: (_) => tap(), visualDensity: VisualDensity.compact),
        );
    final label = _labels.where((l) => l['id'] == _labelId).map((l) => '${l['name']}').firstOrNull;
    String d(DateTime x) => '${x.day}/${x.month}';
    return Column(children: [
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(children: [
          chip('All', _view == 'all', () => _set(() => _view = 'all')),
          chip('Saved', _view == 'named', () => _set(() => _view = 'named')),
          chip('Unsaved numbers', _view == 'unsaved', () => _set(() => _view = 'unsaved'), icon: Icons.person_off_outlined),
          chip('A → Z', _az, () => _set(() => _az = !_az), icon: Icons.sort_by_alpha_rounded),
          if (_labels.isNotEmpty)
            PopupMenuButton<int?>(
              onSelected: (v) => _set(() => _labelId = v),
              itemBuilder: (_) => [
                const PopupMenuItem<int?>(value: null, child: Text('All labels')),
                for (final l in _labels) PopupMenuItem<int?>(value: l['id'] as int?, child: Text('${l['name']}')),
              ],
              child: Padding(padding: const EdgeInsets.only(right: 6), child: Chip(avatar: const Icon(Icons.label_outline_rounded, size: 16), label: Text(label ?? 'Label'), visualDensity: VisualDensity.compact, backgroundColor: _labelId == null ? null : AppColors.primary.withValues(alpha: 0.15))),
            ),
          chip(_created == null ? 'Created date' : '${d(_created!.start)} – ${d(_created!.end)}', _created != null, () async {
            final r = await showDateRangePicker(context: context, firstDate: DateTime(2020), lastDate: DateTime.now().add(const Duration(days: 1)), initialDateRange: _created);
            if (r != null) _set(() => _created = r);
          }, icon: Icons.date_range_rounded),
          if (_view != 'all' || _letter != null || _labelId != null || _created != null || _az)
            ActionChip(label: const Text('Clear'), visualDensity: VisualDensity.compact, onPressed: () => _set(() { _view = 'all'; _letter = null; _labelId = null; _created = null; _az = false; })),
        ]),
      ),
      SizedBox(
        height: 34,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          children: [
            for (final l in [...'ABCDEFGHIJKLMNOPQRSTUVWXYZ'.split(''), '#'])
              InkWell(
                onTap: () => _set(() => _letter = _letter == l ? null : l),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 28,
                  alignment: Alignment.center,
                  margin: const EdgeInsets.symmetric(horizontal: 1, vertical: 4),
                  decoration: BoxDecoration(color: _letter == l ? AppColors.primary : null, borderRadius: BorderRadius.circular(8)),
                  child: Text(l, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: _letter == l ? Colors.white : AppColors.textSecondary)),
                ),
              ),
          ],
        ),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    // The bottom-nav tab bypasses the module catalogue's own permission gating entirely (it's
    // hardcoded in MainShell, not driven by AppModules) — self-check here so a role without
    // contacts access can't reach it just by tapping the tab.
    if (!PermissionGuard.can('contacts.view')) {
      return Scaffold(
        appBar: AppBar(title: const Text('Contacts')),
        body: Center(
          child: Text("You don't have access to this section",
              style: TextStyle(color: context.mutedColor)),
        ),
      );
    }

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createContact,
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('New contact'),
      ),
      appBar: AppBar(
        title: const Text('Contacts'),
        actions: [
          IconButton(icon: const Icon(Icons.add_circle_outline), onPressed: _createContact),
          IconButton(icon: const Icon(Icons.notifications_outlined), onPressed: () => context.push('/notifications')),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchCtrl,
              decoration: const InputDecoration(
                hintText: 'Search name or phone...',
                prefixIcon: Icon(Icons.search, color: AppColors.textLight),
                hintStyle: TextStyle(color: AppColors.textLight),
              ),
            ),
          ),
          _filters(context),
          Expanded(
            child: _loading && _contacts.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : _contacts.isEmpty
                    ? AppEmptyState(icon: Icons.contacts_outlined, title: 'No contacts', subtitle: 'No contacts found.')
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          itemCount: _contacts.length,
                          separatorBuilder: (_, __) => const Divider(height: 1, indent: 68),
                          itemBuilder: (_, i) {
                            final c = _contacts[i];
                            final name  = c['name'] as String? ?? 'Unknown';
                            final phone = c['phone'] as String? ?? '';
                            final score = c['lead_score'] as int? ?? 0;
                            return ListTile(
                              onTap: () => context.push('/contacts/${c['id']}'),
                              leading: AppAvatar(name: name, size: 46),
                              title: Row(
                                children: [
                                  Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.w700))),
                                  if (score > 0) LeadScoreBadge(score: score),
                                ],
                              ),
                              subtitle: Text(FormatUtils.phone(phone), style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

/// "New contact" form as a tall sheet — used by the Contacts tab and the Sales dashboard's quick action. True when a contact was created.
Future<bool> showNewContactSheet(BuildContext context) async {
  final data = <String, dynamic>{};
  final ok = await showFormSheet(
    context,
    title: 'New contact',
    submitLabel: 'Create',
    fields: (ctx) => [
      FText(
        label: 'Phone',
        required: true,
        keyboardType: TextInputType.phone,
        hint: 'With country code',
        onSaved: (v) => data['phone'] = v,
      ),
      FText(label: 'Name', onSaved: (v) => v.isEmpty ? null : data['name'] = v),
      FText(
        label: 'Email',
        keyboardType: TextInputType.emailAddress,
        onSaved: (v) => v.isEmpty ? null : data['email'] = v,
      ),
      FBoolField(
        label: 'Opted in to messaging',
        initial: true,
        onSaved: (v) => data['opted_in'] = v,
      ),
    ],
    onSubmit: () => Api.post('/contacts', data: data),
  );
  return ok;
}

