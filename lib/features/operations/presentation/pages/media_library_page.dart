// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'module_providers.dart';
import 'ops_pages.dart' show pickAndUploadMedia;
import '_shared.dart';

class MediaLibraryPage extends ConsumerWidget {
  const MediaLibraryPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Media Library'),
          bottom: const TabBar(tabs: [
            Tab(text: 'Files'),
            Tab(text: 'Folders'),
          ]),
        ),
        floatingActionButton: Builder(
          builder: (tabCtx) {
            final idx = DefaultTabController.of(tabCtx).index;
            return FloatingActionButton.extended(
              onPressed: () async {
                if (idx == 0) {
                  final ok = await pickAndUploadMedia(tabCtx);
                  if (ok) ref.invalidate(mediaLibraryProvider);
                } else {
                  final data = <String, dynamic>{};
                  final ok = await showFormSheet(
                    tabCtx,
                    title: 'New folder',
                    submitLabel: 'Create',
                    fields: (c) => [
                      FText(
                          label: 'Folder name',
                          required: true,
                          onSaved: (v) => data['name'] = v),
                    ],
                    onSubmit: () =>
                        Api.post('/media-library/folders', data: data),
                  );
                  if (ok) ref.invalidate(mediaFoldersProvider);
                }
              },
              icon: Icon(idx == 0
                  ? Icons.upload_rounded
                  : Icons.create_new_folder_rounded),
              label: Text(idx == 0 ? 'Upload' : 'New folder'),
            );
          },
        ),
        body: TabBarView(children: [
          ProviderList(
            provider: mediaLibraryProvider,
            emptyLabel: 'No media files',
            emptyIcon: Icons.perm_media_rounded,
            tile: (context, m) => RecordCard(
              title: str(m['name'] ?? m['filename'] ?? m['original_name'], 'File'),
              subtitle:
                  '${str(m['mime_type'] ?? m['type'] ?? m['extension'])} · ${_size(m['size'] ?? m['file_size'])}',
              leadingIcon: switch (
                  '${m['mime_type'] ?? m['type'] ?? ''}'.toLowerCase()) {
                final t when t.contains('image') => Icons.image_rounded,
                final t when t.contains('video') => Icons.videocam_rounded,
                final t when t.contains('audio') => Icons.audiotrack_rounded,
                final t when t.contains('pdf') => Icons.picture_as_pdf_rounded,
                _ => Icons.insert_drive_file_rounded,
              },
              trailing: RowMenu(items: [
                (
                  'Rename',
                  Icons.drive_file_rename_outline_rounded,
                  () async {
                    final data = <String, dynamic>{};
                    final ok = await showFormSheet(
                      context,
                      title: 'Rename file',
                      submitLabel: 'Rename',
                      fields: (c) => [
                        FText(
                            label: 'Name',
                            required: true,
                            initial: str(m['name'] ?? m['filename']),
                            onSaved: (v) => data['name'] = v),
                      ],
                      onSubmit: () => Api.patch(
                          '/media-library/${m['id']}/rename',
                          data: data),
                    );
                    if (ok) ref.invalidate(mediaLibraryProvider);
                  }
                ),
                (
                  'Delete',
                  Icons.delete_rounded,
                  () async {
                    if (!await confirm(context,
                        title: 'Delete file?',
                        destructive: true,
                        confirmLabel: 'Delete')) { return; }
                    final ok = await runAction(context,
                        () => Api.delete('/media-library/${m['id']}'),
                        success: 'Deleted');
                    if (ok) ref.invalidate(mediaLibraryProvider);
                  }
                ),
              ]),
            ),
          ),
          ProviderList(
            provider: mediaFoldersProvider,
            emptyLabel: 'No folders',
            emptyIcon: Icons.folder_rounded,
            tile: (context, f) => RecordCard(
              title: str(f['name']),
              subtitle:
                  '${str(f['files_count'] ?? f['media_count'] ?? '0')} files',
              leadingIcon: Icons.folder_rounded,
              leadingColor: AppPalette.warning,
              trailing: RowMenu(items: [
                (
                  'Rename',
                  Icons.drive_file_rename_outline_rounded,
                  () async {
                    final data = <String, dynamic>{};
                    final ok = await showFormSheet(
                      context,
                      title: 'Rename folder',
                      submitLabel: 'Rename',
                      fields: (c) => [
                        FText(
                            label: 'Name',
                            required: true,
                            initial: str(f['name']),
                            onSaved: (v) => data['name'] = v),
                      ],
                      onSubmit: () => Api.patch(
                          '/media-library/folders/${f['id']}',
                          data: data),
                    );
                    if (ok) ref.invalidate(mediaFoldersProvider);
                  }
                ),
                (
                  'Delete',
                  Icons.delete_rounded,
                  () async {
                    if (!await confirm(context,
                        title: 'Delete folder?',
                        destructive: true,
                        confirmLabel: 'Delete')) { return; }
                    final ok = await runAction(
                        context,
                        () => Api.delete('/media-library/folders/${f['id']}'),
                        success: 'Deleted');
                    if (ok) ref.invalidate(mediaFoldersProvider);
                  }
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  String _size(Object? bytes) {
    final b = num.tryParse('${bytes ?? 0}') ?? 0;
    if (b >= 1e9) return '${(b / 1e9).toStringAsFixed(1)} GB';
    if (b >= 1e6) return '${(b / 1e6).toStringAsFixed(1)} MB';
    if (b >= 1e3) return '${(b / 1e3).toStringAsFixed(0)} KB';
    return '$b B';
  }
}
