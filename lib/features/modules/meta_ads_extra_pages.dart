// ignore_for_file: use_build_context_synchronously
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'module_providers.dart';
import '_shared.dart';

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

// ══════════════════════════ Creative Studio ══════════════════════════

// Carousel isn't offered here — it needs 2-10 per-card fields the mobile
// builder doesn't have UI for yet; users needing it are pointed to the web app.
const _creativeFormats = ['image', 'video'];
const _ctaOptions = [
  'LEARN_MORE', 'SIGN_UP', 'SHOP_NOW', 'GET_QUOTE', 'CONTACT_US',
  'BOOK_NOW', 'DOWNLOAD', 'WATCH_MORE', 'APPLY_NOW', 'GET_OFFER',
];

class CreativeStudioPage extends ConsumerWidget {
  const CreativeStudioPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Creative Studio'),
          bottom: const TabBar(tabs: [Tab(text: 'Media Library'), Tab(text: 'Creatives')]),
        ),
        body: const TabBarView(children: [_MediaLibraryTab(), _CreativesTab()]),
      ),
    );
  }
}

class _MediaLibraryTab extends ConsumerStatefulWidget {
  const _MediaLibraryTab();
  @override
  ConsumerState<_MediaLibraryTab> createState() => _MediaLibraryTabState();
}

class _MediaLibraryTabState extends ConsumerState<_MediaLibraryTab> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _upload(context),
        icon: const Icon(Icons.upload_rounded),
        label: const Text('Upload'),
      ),
      body: ProviderList(
        provider: metaMediaLibraryProvider,
        emptyLabel: 'No media uploaded yet',
        emptyIcon: Icons.perm_media_outlined,
        tile: (context, m) {
          final isVideo = m['type'] == 'video';
          return RecordCard(
            title: str(m['name'] ?? m['original_filename'], 'Untitled'),
            subtitle: '${isVideo ? 'Video' : 'Image'}'
                '${m['width'] != null ? ' · ${m['width']}×${m['height']}' : ''}'
                '${m['duration_seconds'] != null ? ' · ${m['duration_seconds']}s' : ''}',
            leadingIcon: isVideo ? Icons.videocam_rounded : Icons.image_rounded,
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              StatusPill(str(m['upload_status'], 'ready')),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                onPressed: () async {
                  final sure = await confirm(context, title: 'Delete this media?', destructive: true, confirmLabel: 'Delete');
                  if (!sure) return;
                  final done = await runAction(context, () => Api.delete('/meta-ads/media/${m['id']}'), success: 'Deleted');
                  if (done) ref.invalidate(metaMediaLibraryProvider);
                },
              ),
            ]),
          );
        },
      ),
    );
  }

  Future<void> _upload(BuildContext context) async {
    List<Rec> accounts;
    try {
      accounts = await Api.list('/meta-ads/accounts');
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
      return;
    }
    if (accounts.isEmpty) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Connect a Meta ad account first.')));
      return;
    }
    if (!context.mounted) return;
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(children: [
          ListTile(leading: const Icon(Icons.image_rounded), title: const Text('Upload image'), onTap: () => Navigator.pop(ctx, 'image')),
          ListTile(leading: const Icon(Icons.videocam_rounded), title: const Text('Upload video'), onTap: () => Navigator.pop(ctx, 'video')),
        ]),
      ),
    );
    if (choice == null || !context.mounted) return;

    Rec? account = accounts.length == 1 ? accounts.first : null;
    if (account == null) {
      await showFormSheet(
        context,
        title: 'Select ad account',
        submitLabel: 'Continue',
        fields: (ctx) => [FSelect<Rec>(label: 'Account', options: accounts, labelOf: (a) => str(a['name']), onSaved: (a) => account = a)],
        onSubmit: () async {},
      );
    }
    if (account == null || !context.mounted) return;

    final picker = ImagePicker();
    final file = choice == 'image'
        ? await picker.pickImage(source: ImageSource.gallery, imageQuality: 90)
        : await picker.pickVideo(source: ImageSource.gallery);
    if (file == null || !context.mounted) return;

    try {
      final form = FormData.fromMap({
        'account_id': account!['id'],
        'file': await MultipartFile.fromFile(file.path, filename: file.name),
        if (choice == 'video') 'title': file.name,
      });
      await Api.raw.post('/meta-ads/media/upload-${choice == 'image' ? 'image' : 'video'}', data: form);
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Uploaded')));
      ref.invalidate(metaMediaLibraryProvider);
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
    }
  }
}

class _CreativesTab extends ConsumerWidget {
  const _CreativesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _newCreative(context, ref),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New creative'),
      ),
      body: ProviderList(
        provider: metaCreativesProvider,
        emptyLabel: 'No creatives yet',
        emptyIcon: Icons.brush_outlined,
        tile: (context, c) => RecordCard(
          title: str(c['name'], c['headline'] ?? 'Untitled creative'),
          subtitle: '${str(c['format'], 'image').toUpperCase()} · ${str(c['primary_text'], '')}'
              '${c['call_to_action'] != null ? ' · ${c['call_to_action']}' : ''}',
          leadingIcon: switch (c['format']) {
            'video' => Icons.videocam_rounded,
            'carousel' => Icons.view_carousel_rounded,
            _ => Icons.image_rounded,
          },
          trailing: RowMenu(items: [
            ('Delete', Icons.delete_outline_rounded, () async {
              final sure = await confirm(context, title: 'Delete this creative?', destructive: true, confirmLabel: 'Delete');
              if (!sure) return;
              final done = await runAction(context, () => Api.delete('/meta-ads/creatives/${c['id']}'), success: 'Deleted');
              if (done) ref.invalidate(metaCreativesProvider);
            }),
          ]),
        ),
      ),
    );
  }

  Future<void> _newCreative(BuildContext context, WidgetRef ref) async {
    List<Rec> accounts;
    List<Rec> media;
    List<Rec> forms;
    try {
      accounts = await Api.list('/meta-ads/accounts');
      media = await Api.list('/meta-ads/media');
      final formsRes = await Api.one('/meta-ads/lead-forms');
      final formsList = formsRes['forms'];
      forms = formsList is List ? formsList.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList() : [];
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
      return;
    }
    if (accounts.isEmpty) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Connect a Meta ad account first.')));
      return;
    }
    if (!context.mounted) return;

    var format = 'image';
    final images = media.where((m) => m['type'] == 'image').toList();
    final videos = media.where((m) => m['type'] == 'video').toList();
    final data = <String, dynamic>{'account_id': accounts.first['id'], 'format': format};

    if (accounts.length > 1) {
      Rec? account;
      await showFormSheet(
        context,
        title: 'Select ad account',
        submitLabel: 'Continue',
        fields: (ctx) => [FSelect<Rec>(label: 'Account', options: accounts, labelOf: (a) => str(a['name']), onSaved: (a) => account = a)],
        onSubmit: () async {},
      );
      if (account == null) return;
      data['account_id'] = account!['id'];
    }
    if (!context.mounted) return;

    final ok = await showFormSheet(
      context,
      title: 'New creative',
      fields: (ctx) => [
        FSelect<String>(label: 'Format', options: _creativeFormats, initial: 'image',
            onSaved: (v) => data['format'] = v ?? 'image'),
        FText(label: 'Internal name', onSaved: (v) => v.isEmpty ? null : data['name'] = v),
        FText(label: 'Primary text', required: true, maxLines: 3, onSaved: (v) => data['primary_text'] = v),
        FText(label: 'Headline', onSaved: (v) => v.isEmpty ? null : data['headline'] = v),
        FText(label: 'Description', onSaved: (v) => v.isEmpty ? null : data['description'] = v),
        FSelect<String>(label: 'Call to action', options: _ctaOptions, onSaved: (v) => data['call_to_action'] = v),
        if (images.isNotEmpty)
          FSelect<Rec>(label: 'Image (required for image format)', options: images,
              labelOf: (m) => str(m['name'] ?? m['original_filename']), onSaved: (m) => data['image_id'] = m?['id']),
        if (videos.isNotEmpty)
          FSelect<Rec>(label: 'Video (required for video format)', options: videos,
              labelOf: (m) => str(m['name'] ?? m['original_filename']), onSaved: (m) => data['video_id'] = m?['id']),
        FText(label: 'Destination URL (or leave blank to use a Lead Form below)',
            onSaved: (v) => v.isEmpty ? null : data['destination_url'] = v),
        if (forms.isNotEmpty)
          FSelect<Rec>(label: 'Lead form (optional — makes this a lead-ad creative)', options: forms,
              labelOf: (f) => str(f['name']), onSaved: (f) => data['lead_form_id'] = f?['id']),
      ],
      onSubmit: () => Api.post('/meta-ads/creatives', data: data),
    );
    if (ok) ref.invalidate(metaCreativesProvider);
  }
}
