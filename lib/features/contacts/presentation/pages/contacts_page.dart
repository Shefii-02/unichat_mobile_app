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

  @override
  void initState() {
    super.initState();
    _load();
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
        'per_page': 30,
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
    if (ok) _load();
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
