// WA Chat's "Templates" — full CRUD against the Laravel `wa_chat_templates` table
// (`WaChatTemplateController`), a single company-wide template library shared across every WA
// session (not scoped to one session — `index()` filters only by `company_id`). This is the same
// data source the campaign composer's "Template" message tab reads via `waChatTemplatesProvider`.
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mime/mime.dart';
import 'package:unichat_mobile_app/features/modules/_shared.dart';
import 'package:unichat_mobile_app/features/modules/module_providers.dart';

class WaChatTemplatesPage extends ConsumerWidget {
  const WaChatTemplatesPage({super.key});

  static const _headerTypes = ['none', 'text', 'image', 'video', 'document'];
  static const _statuses = ['draft', 'active', 'archived'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('WA Templates')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context, ref, null),
        icon: const Icon(Icons.add_rounded),
        label: const Text('WA New template'),
      ),
      body: ProviderList(
        provider: waChatTemplatesProvider,
        emptyLabel: 'No templates yet',
        emptyIcon: Icons.dashboard_customize_rounded,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
        tile: (context, t) => _templateTile(context, ref, t),
      ),
    );
  }

  Widget _templateTile(BuildContext context, WidgetRef ref, Rec t) {
    final status = str(t['status'], 'draft');
    final statusColor = switch (status) {
      'active' => AppPalette.success,
      'archived' => AppPalette.muted,
      _ => AppPalette.warning,
    };
    return RecordCard(
      title: str(t['name']),
      subtitle: str(t['body'], ''),
      leadingIcon: Icons.dashboard_customize_rounded,
      onTap: () => _edit(context, ref, t),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          StatusPill(status, color: statusColor),
          RowMenu(items: [
            ('Edit', Icons.edit_rounded, () => _edit(context, ref, t)),
            (
              'Delete',
              Icons.delete_rounded,
              () async {
                if (!await confirm(context, title: 'Delete template?', message: 'Delete "${str(t['name'])}"? This cannot be undone.', destructive: true, confirmLabel: 'Delete')) {
                  return;
                }
                final ok = await runAction(context, () => Api.delete('/wa-chat-templates/${t['id']}'), success: 'Deleted');
                if (ok) ref.invalidate(waChatTemplatesProvider);
              },
            ),
          ]),
        ],
      ),
      footer: Wrap(
        spacing: 6,
        children: [
          if (str(t['category'], '').isNotEmpty) StatusPill(str(t['category']), color: AppPalette.info),
          if (str(t['language'], '').isNotEmpty) StatusPill(str(t['language']), color: AppPalette.cold),
        ],
      ),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, Rec? existing) async {
    final creating = existing == null;
    final data = <String, dynamic>{};
    // Mutated in place by _MediaBlocksField below (add/remove/edit block) and captured by
    // reference into `data` right away — no onSaved plumbing needed since it's the same List
    // object throughout, so every later mutation is already reflected in `data['media_blocks']`.
    final mediaBlocks = <Map<String, dynamic>>[
      for (final b in (existing?['media_blocks'] as List? ?? [])) Map<String, dynamic>.from(b as Map),
    ];
    data['media_blocks'] = mediaBlocks;
    final ok = await showFormSheet(
      context,
      title: creating ? 'New template' : 'Edit template',
      submitLabel: creating ? 'Create' : 'Save',
      fields: (ctx) => [
        FText(label: 'Name', required: true, initial: existing?['name'] as String?, onSaved: (v) => data['name'] = v),
        // FText(label: 'Category', required: true, hint: 'e.g. marketing, utility', initial: existing?['category'] as String?, onSaved: (v) => data['category'] = v),
        // FText(label: 'Language (optional)', hint: 'e.g. en, hi', initial: existing?['language'] as String?, onSaved: (v) => v.isEmpty ? null : data['language'] = v),
        FSelect<String>(
          label: 'Header type',
          options: _headerTypes,
          initial: str(existing?['header_type'], 'none'),
          onSaved: (v) => data['header_type'] = v == 'none' ? null : v,
        ),
        FText(label: 'Header content (optional)', hint: 'Text, or a media URL for image/video/document', initial: existing?['header_content'] as String?, onSaved: (v) => v.isEmpty ? null : data['header_content'] = v),
        FText(label: 'Body', required: true, maxLines: 6, initial: existing?['body'] as String?, onSaved: (v) => data['body'] = v),
        FText(label: 'Footer (optional)', initial: existing?['footer'] as String?, onSaved: (v) => v.isEmpty ? null : data['footer'] = v),
        _MediaBlocksField(blocks: mediaBlocks),
        FSelect<String>(
          label: 'Status',
          options: _statuses,
          initial: str(existing?['status'], 'draft'),
          onSaved: (v) => data['status'] = v,
        ),
      ],
      onSubmit: () => creating ? Api.post('/wa-chat-templates', data: data) : Api.patch('/wa-chat-templates/${existing['id']}', data: data),
    );
    if (ok) ref.invalidate(waChatTemplatesProvider);
  }
}

/// "Additional Media Blocks" — extra messages sent right after the main body, each its own type
/// (text/image/video/audio/document). Mirrors the campaign composer's Multi Media block editor
/// (`campaign_composer.dart`'s `_mediaBlockCard`) so the same block shape (`{type, text?,
/// mediaUrl?, caption?}`) round-trips between a template's `media_blocks` and a campaign that
/// later loads this template — see ProcessMessageSenderJob.php's `sendMediaBlocks`.
class _MediaBlocksField extends StatefulWidget {
  const _MediaBlocksField({required this.blocks});
  final List<Map<String, dynamic>> blocks;

  @override
  State<_MediaBlocksField> createState() => _MediaBlocksFieldState();
}

class _MediaBlocksFieldState extends State<_MediaBlocksField> {
  static const _types = ['text', 'image', 'video', 'audio', 'document'];

  @override
  Widget build(BuildContext context) {
    return FField(
      label: 'Additional Media Blocks',
      hint: 'Sent as separate messages after the body',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < widget.blocks.length; i++) _blockCard(context, i),
          OutlinedButton.icon(
            onPressed: () => setState(() => widget.blocks.add({'type': 'text', 'text': ''})),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Add Media Block'),
          ),
        ],
      ),
    );
  }

  Widget _blockCard(BuildContext context, int index) {
    final block = widget.blocks[index];
    final type = str(block['type'], 'text');
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(border: Border.all(color: context.lineColor), borderRadius: BorderRadius.circular(8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text('Block ${index + 1}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
            const Spacer(),
            IconButton(
              onPressed: () => setState(() => widget.blocks.removeAt(index)),
              icon: const Icon(Icons.delete_outline_rounded, size: 18, color: AppPalette.danger),
            ),
          ]),
          DropdownButtonFormField<String>(
            initialValue: _types.contains(type) ? type : 'text',
            isDense: true,
            items: _types.map((t) => DropdownMenuItem(value: t, child: Text(t[0].toUpperCase() + t.substring(1)))).toList(),
            onChanged: (v) => setState(() => block['type'] = v ?? 'text'),
          ),
          const SizedBox(height: 8),
          if (type == 'text')
            TextFormField(
              initialValue: str(block['text'], ''),
              maxLines: 3,
              decoration: const InputDecoration(hintText: 'Text content… {{name}} {{phone}}', isDense: true),
              onChanged: (v) => block['text'] = v,
            )
          else ...[
            // A fresh controller each build (not persisted) is deliberate: Upload/Browse Library
            // below set `block['mediaUrl']` and call setState, and only a brand-new controller's
            // `text:` actually reflects that — TextFormField's `initialValue` is read once in
            // initState and ignored on every rebuild after, so a persisted controller would leave
            // the field showing the stale (empty) value after a pick.
            TextFormField(
              controller: TextEditingController(text: str(block['mediaUrl'], '')),
              decoration: const InputDecoration(hintText: 'Media URL', isDense: true),
              onChanged: (v) => block['mediaUrl'] = v,
            ),
            const SizedBox(height: 6),
            Row(children: [
              TextButton.icon(
                onPressed: () => _pickFile(block),
                icon: const Icon(Icons.upload_file_rounded, size: 16),
                label: const Text('Upload'),
              ),
              TextButton.icon(
                onPressed: () => _browseLibrary(block),
                icon: const Text('🗂️', style: TextStyle(fontSize: 14)),
                label: const Text('Browse Library'),
              ),
            ]),
            const SizedBox(height: 8),
            TextFormField(
              initialValue: str(block['caption'], ''),
              decoration: const InputDecoration(hintText: 'Caption (optional)', isDense: true),
              onChanged: (v) => block['caption'] = v,
            ),
          ],
        ],
      ),
    );
  }

  Future<String?> _uploadFile(String path, String filename) async {
    final mimetype = lookupMimeType(path) ?? 'application/octet-stream';
    final res = await Api.raw.post(
      '/media-library/upload',
      data: FormData.fromMap({
        'file': await MultipartFile.fromFile(path, filename: filename, contentType: DioMediaType.parse(mimetype)),
      }),
    );
    final data = res.data;
    return data is Map && data['url'] is String ? data['url'] as String : null;
  }

  Future<void> _pickFile(Map<String, dynamic> block) async {
    final result = await FilePicker.platform.pickFiles(withData: false);
    final picked = result?.files.single;
    if (picked?.path == null) return;
    try {
      final url = await _uploadFile(picked!.path!, picked.name);
      if (url == null) throw Exception('Upload did not return a URL.');
      setState(() { block['mediaUrl'] = url; block['filename'] = picked.name; });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Couldn't upload — ${apiErrorMessage(e)}")));
    }
  }

  static const _libraryTypeByMime = {'image': 'image', 'video': 'video', 'audio': 'audio'};

  Future<void> _browseLibrary(Map<String, dynamic> block) async {
    List<Rec> files;
    try {
      files = await Api.list('/media-library');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Couldn't load media library — ${apiErrorMessage(e)}")));
      return;
    }
    if (!mounted) return;
    final picked = await showModalBottomSheet<Rec>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        expand: false,
        builder: (ctx, scrollCtrl) => files.isEmpty
            ? Center(child: Text('Media Library is empty', style: TextStyle(color: ctx.mutedColor)))
            : ListView.separated(
                controller: scrollCtrl,
                padding: const EdgeInsets.all(16),
                itemCount: files.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (_, i) {
                  final f = files[i];
                  final mime = str(f['mime_type'], '');
                  final kind = _libraryTypeByMime[mime.split('/').first] ?? 'document';
                  final url = str(f['url'], '');
                  return ListTile(
                    dense: true,
                    leading: kind == 'image' && url.isNotEmpty
                        ? CircleAvatar(radius: 20, backgroundImage: NetworkImage(url), onBackgroundImageError: (_, __) {}, child: const SizedBox.shrink())
                        : CircleAvatar(
                            radius: 20,
                            child: Icon(switch (kind) {
                              'video' => Icons.videocam_rounded,
                              'audio' => Icons.audiotrack_rounded,
                              _ => Icons.insert_drive_file_rounded,
                            }),
                          ),
                    title: Text(str(f['display_name'] ?? f['original_name'], 'File'), maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(mime, style: const TextStyle(fontSize: 11)),
                    onTap: () => Navigator.pop(ctx, f),
                  );
                },
              ),
      ),
    );
    if (picked == null) return;
    final mime = str(picked['mime_type'], '');
    setState(() {
      block['type'] = _libraryTypeByMime[mime.split('/').first] ?? 'document';
      block['mediaUrl'] = str(picked['url'], '');
      block['filename'] = str(picked['display_name'] ?? picked['original_name'], '');
    });
  }
}
