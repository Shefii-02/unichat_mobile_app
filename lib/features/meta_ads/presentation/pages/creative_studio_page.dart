// ignore_for_file: use_build_context_synchronously
import "package:dio/dio.dart";
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:image_picker/image_picker.dart";
import "package:unichat_mobile_app/features/modules/module_providers.dart";
import "package:unichat_mobile_app/features/modules/_shared.dart";

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
