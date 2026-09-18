// ignore_for_file: use_build_context_synchronously
import "package:dio/dio.dart";
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:image_picker/image_picker.dart";
import "package:unichat_mobile_app/features/modules/module_providers.dart";
import "package:unichat_mobile_app/features/modules/_shared.dart";

// ══════════════════════════ Lead Ads ══════════════════════════

const _leadStatuses = ['pending', 'processed', 'failed', 'skipped'];

class LeadAdsPage extends ConsumerWidget {
  const LeadAdsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Lead Ads'),
          bottom: const TabBar(tabs: [Tab(text: 'Forms'), Tab(text: 'Leads')]),
        ),
        body: TabBarView(children: [
          _FormsTab(),
          const _CapturedLeadsTab(),
        ]),
      ),
    );
  }
}

class _FormsTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.extended(
            heroTag: 'sync',
            onPressed: () => _syncForms(context, ref),
            icon: const Icon(Icons.sync_rounded),
            label: const Text('Sync forms'),
          ),
          const SizedBox(height: 10),
          FloatingActionButton.extended(
            heroTag: 'new',
            onPressed: () => _newForm(context, ref),
            icon: const Icon(Icons.add_rounded),
            label: const Text('New form'),
          ),
        ],
      ),
      body: ProviderList(
        provider: metaLeadFormsProvider,
        emptyLabel: 'No Instant Forms yet — sync from your ad account',
        emptyIcon: Icons.fact_check_outlined,
        tile: (context, f) => RecordCard(
          title: str(f['name']),
          subtitle: '${str(f['status'], 'ACTIVE')} · ${f['leads_count'] ?? 0} leads on Meta · ${f['crm_leads_count'] ?? 0} in CRM'
              '${f['last_synced_at'] != null ? ' · Synced ${when(f['last_synced_at'])}' : ''}',
          leadingIcon: Icons.fact_check_rounded,
          trailing: RowMenu(items: [
            ('Import missed leads', Icons.download_rounded, () async {
              final ok = await runAction(context, () => Api.post('/meta-ads/lead-forms/${f['id']}/sync-leads'), success: 'Leads imported');
              if (ok) { ref.invalidate(metaLeadFormsProvider); ref.invalidate(metaLeadsProvider); }
            }),
          ]),
        ),
      ),
    );
  }

  Future<Rec?> _pickAccount(BuildContext context) async {
    List<Rec> accounts;
    try {
      accounts = await Api.list('/meta-ads/accounts');
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
      return null;
    }
    if (accounts.isEmpty) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Connect a Meta ad account first.')));
      return null;
    }
    if (accounts.length == 1) return accounts.first;
    if (!context.mounted) return null;
    Rec? picked;
    await showFormSheet(
      context,
      title: 'Select ad account',
      submitLabel: 'Continue',
      fields: (ctx) => [
        FSelect<Rec>(label: 'Account', options: accounts, labelOf: (a) => str(a['name']), onSaved: (a) => picked = a),
      ],
      onSubmit: () async {},
    );
    return picked;
  }

  Future<void> _syncForms(BuildContext context, WidgetRef ref) async {
    final account = await _pickAccount(context);
    if (account == null || !context.mounted) return;
    final ok = await runAction(context, () => Api.post('/meta-ads/lead-forms/sync', data: {'account_id': account['id']}), success: 'Forms synced');
    if (ok) ref.invalidate(metaLeadFormsProvider);
  }

  Future<void> _newForm(BuildContext context, WidgetRef ref) async {
    final account = await _pickAccount(context);
    if (account == null || !context.mounted) return;
    final data = <String, dynamic>{'account_id': account['id']};
    final ok = await showFormSheet(
      context,
      title: 'New Instant Form',
      fields: (ctx) => [
        FText(label: 'Form name', required: true, onSaved: (v) => data['name'] = v),
        FText(label: 'Privacy policy URL', onSaved: (v) => v.isEmpty ? null : data['privacy_url'] = v),
      ],
      onSubmit: () => Api.post('/meta-ads/lead-forms', data: data),
    );
    if (ok) ref.invalidate(metaLeadFormsProvider);
  }
}

class _CapturedLeadsTab extends StatefulWidget {
  const _CapturedLeadsTab();
  @override
  State<_CapturedLeadsTab> createState() => _CapturedLeadsTabState();
}

class _CapturedLeadsTabState extends State<_CapturedLeadsTab> {
  List<Rec> _leads = [];
  bool _loading = true;
  String? _status;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rows = await Api.list('/meta-ads/leads', query: {if (_status != null) 'status': _status});
      setState(() { _leads = rows; _loading = false; });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(label: const Text('All'), selected: _status == null, onSelected: (_) { setState(() => _status = null); _load(); }),
              ),
              for (final s in _leadStatuses)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(label: Text(s), selected: _status == s, onSelected: (_) { setState(() => _status = s); _load(); }),
                ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _leads.isEmpty
                  ? Center(child: Text('No captured leads', style: TextStyle(color: context.mutedColor)))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: _leads.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          final l = _leads[i];
                          final form = (l['form'] is Map) ? l['form'] as Map : const {};
                          final campaign = (l['campaign'] is Map) ? l['campaign'] as Map : const {};
                          return RecordCard(
                            title: str(l['full_name'], 'Unknown'),
                            subtitle: [
                              str(l['phone'], ''),
                              if (form['name'] != null) form['name'],
                              if (campaign['name'] != null) campaign['name'],
                              when(l['meta_created_time']),
                            ].where((s) => s != null && '$s'.isNotEmpty).join(' · '),
                            leadingIcon: Icons.person_add_alt_1_rounded,
                            trailing: StatusPill(str(l['process_status'], 'pending')),
                          );
                        },
                      ),
                    ),
        ),
      ],
    );
  }
}

