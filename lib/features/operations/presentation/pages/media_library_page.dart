// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:unichat_mobile_app/features/operations/data/media_upload_helper.dart';
import 'package:unichat_mobile_app/features/modules/_shared.dart';

/// WA Chat's "Media Library" quick link — folder-aware grid, mirroring
/// frontend/src/pages/wa-chat/pages/WaMediaLibrary.tsx: create folders, drill into a
/// folder to see/upload its files, and copy/move/delete files between folders.
/// At the root, folders are listed first (name asc), then all files (created_at desc);
/// inside a folder, only that folder's files are shown.
class MediaLibraryPage extends ConsumerStatefulWidget {
  const MediaLibraryPage({super.key});
  @override
  ConsumerState<MediaLibraryPage> createState() => _MediaLibraryPageState();
}

/// One paged list of files (a folder's, or everything): pages of [pageSize] are fetched as the user scrolls near the end.
class _Pager {
  final items = <Rec>[];
  int page = 0;
  bool hasMore = true;
  bool loading = false;
  Object? error;
  void reset() { items.clear(); page = 0; hasMore = true; loading = false; error = null; }
}

const _pageSize = 30;

class _MediaLibraryPageState extends ConsumerState<MediaLibraryPage> with SingleTickerProviderStateMixin {
  List<Rec> _folders = [];
  bool _loadingFolders = true;
  Object? _foldersError;
  final List<Rec> _path = []; // folders opened in the Folders tab, root → current
  final _all = _Pager();      // "All files" tab
  final _inFolder = _Pager(); // files of the folder being viewed
  final _allScroll = ScrollController();
  final _folderScroll = ScrollController();
  late final TabController _tabs = TabController(length: 2, vsync: this);

  Rec? get _activeFolder => _path.isEmpty ? null : _path.last;

  @override
  void initState() {
    super.initState();
    _allScroll.addListener(() => _maybeMore(_allScroll, _all, null));
    _folderScroll.addListener(() => _maybeMore(_folderScroll, _inFolder, _activeFolder));
    _tabs.addListener(() { if (mounted) setState(() {}); });
    _loadFolders();
    _loadMore(_all, null);
  }

  @override
  void dispose() {
    _allScroll.dispose();
    _folderScroll.dispose();
    _tabs.dispose();
    super.dispose();
  }

  void _maybeMore(ScrollController c, _Pager pager, Rec? folder) {
    if (c.hasClients && c.position.pixels >= c.position.maxScrollExtent - 300) _loadMore(pager, folder);
  }

  Future<void> _loadMore(_Pager pager, Rec? folder) async {
    if (pager.loading || !pager.hasMore) return;
    setState(() { pager.loading = true; pager.error = null; });
    try {
      final res = await Api.raw.get('/media-library', queryParameters: {
        'per_page': _pageSize,
        'page': pager.page + 1,
        if (folder != null) 'folder_id': folder['id'],
      });
      final body = res.data is Map ? res.data as Map : const {};
      final rows = (body['data'] as List? ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      final meta = body['meta'] is Map ? body['meta'] as Map : const {};
      if (!mounted) return;
      setState(() {
        pager.items.addAll(rows);
        pager.page = (meta['current_page'] as num?)?.toInt() ?? pager.page + 1;
        pager.hasMore = pager.page < ((meta['last_page'] as num?)?.toInt() ?? pager.page);
      });
    } catch (e) {
      if (mounted) setState(() { pager.error = e; pager.hasMore = false; });
    } finally {
      if (mounted) setState(() => pager.loading = false);
    }
  }

  Future<void> _loadFolders() async {
    setState(() { _loadingFolders = true; _foldersError = null; });
    try {
      final folders = await Api.list('/media-library/folders');
      if (mounted) setState(() { _folders = folders; _loadingFolders = false; });
    } catch (e) {
      if (mounted) setState(() { _foldersError = e; _loadingFolders = false; });
    }
  }

  /// Reload whatever is on screen (used after rename / upload / delete).
  Future<void> _loadFiles() async {
    _all.reset();
    _inFolder.reset();
    await Future.wait([_loadMore(_all, null), if (_activeFolder != null) _loadMore(_inFolder, _activeFolder)]);
  }

  Future<void> _refreshAll() async {
    await Future.wait([_loadFolders(), _loadFiles()]);
  }

  void _openFolder(Rec f) {
    setState(() { _path.add(f); _inFolder.reset(); });
    _tabs.animateTo(0);
    _loadMore(_inFolder, f);
  }

  void _goUp() {
    setState(() { _path.removeLast(); _inFolder.reset(); });
    if (_activeFolder != null) _loadMore(_inFolder, _activeFolder);
  }

  void _goToRoot() {
    setState(() { _path.clear(); _inFolder.reset(); });
  }

  /// Folders shown now: top-level ones at the root, otherwise the children of the open folder.
  List<Rec> get _visibleFolders {
    final pid = _activeFolder?['id'];
    final list = _folders.where((f) => f['parent_id'] == pid).toList();
    list.sort((a, b) => str(a['name']).toLowerCase().compareTo(str(b['name']).toLowerCase()));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final insideFolder = _activeFolder != null;
    return PopScope(
      canPop: !(insideFolder && _tabs.index == 0),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && insideFolder) _goUp();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: insideFolder && _tabs.index == 0 ? IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: _goUp) : null,
          title: Text(insideFolder && _tabs.index == 0 ? str(_activeFolder!['name'], 'Folder') : 'Media Library'),
          bottom: TabBar(controller: _tabs, tabs: const [Tab(text: 'Folders'), Tab(text: 'All files')]),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () => _showAddMenu(context),
          child: const Icon(Icons.add_rounded),
        ),
        body: TabBarView(controller: _tabs, children: [_foldersTab(context), _allFilesTab(context)]),
      ),
    );
  }

  Widget _errorView(Object err) => ListView(padding: const EdgeInsets.all(32), children: [
        const SizedBox(height: 100),
        const Icon(Icons.error_outline_rounded, size: 48, color: AppPalette.danger),
        const SizedBox(height: 12),
        Text(apiErrorMessage(err), textAlign: TextAlign.center, style: TextStyle(color: context.mutedColor)),
        const SizedBox(height: 16),
        Center(child: OutlinedButton.icon(onPressed: _refreshAll, icon: const Icon(Icons.refresh_rounded), label: const Text('Retry'))),
      ]);

  Widget _emptyView(IconData icon, String text) => ListView(children: [
        const SizedBox(height: 140),
        Icon(icon, size: 56, color: context.mutedColor),
        const SizedBox(height: 12),
        Center(child: Text(text, style: TextStyle(color: context.mutedColor))),
      ]);

  /// Folders (and, inside one, its files) — drill down with the back button.
  Widget _foldersTab(BuildContext context) {
    if (_loadingFolders && _folders.isEmpty) return ListView(children: const [SizedBox(height: 180), Center(child: CircularProgressIndicator())]);
    if (_foldersError != null) return RefreshIndicator(onRefresh: _refreshAll, child: _errorView(_foldersError!));
    final folders = _visibleFolders;
    final inside = _activeFolder != null;
    final showFiles = inside;
    if (folders.isEmpty && (!showFiles || (_inFolder.items.isEmpty && !_inFolder.loading))) {
      return RefreshIndicator(
        onRefresh: _refreshAll,
        child: _emptyView(inside ? Icons.perm_media_rounded : Icons.folder_open_rounded, inside ? 'This folder is empty' : 'No folders yet'),
      );
    }
    return RefreshIndicator(
      onRefresh: _refreshAll,
      child: _fileGrid(context, controller: _folderScroll, folders: folders, files: showFiles ? _inFolder.items : const [], pager: showFiles ? _inFolder : null),
    );
  }

  /// Every file in the library, newest first, loaded a page at a time.
  Widget _allFilesTab(BuildContext context) {
    if (_all.error != null && _all.items.isEmpty) return RefreshIndicator(onRefresh: _refreshAll, child: _errorView(_all.error!));
    if (_all.loading && _all.items.isEmpty) return ListView(children: const [SizedBox(height: 180), Center(child: CircularProgressIndicator())]);
    if (_all.items.isEmpty) return RefreshIndicator(onRefresh: _refreshAll, child: _emptyView(Icons.perm_media_rounded, 'No media files yet'));
    return RefreshIndicator(
      onRefresh: _refreshAll,
      child: _fileGrid(context, controller: _allScroll, folders: const [], files: _all.items, pager: _all),
    );
  }

  Widget _fileGrid(BuildContext context, {required ScrollController controller, required List<Rec> folders, required List<Rec> files, required _Pager? pager}) {
    return CustomScrollView(
      controller: controller,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 130, mainAxisSpacing: 14, crossAxisSpacing: 12, childAspectRatio: 0.8),
            delegate: SliverChildBuilderDelegate(
              (context, i) => i < folders.length ? _folderTile(context, folders[i]) : _fileTile(context, files[i - folders.length]),
              childCount: folders.length + files.length,
            ),
          ),
        ),
        if (pager != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: Center(
                child: pager.loading
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                    : pager.error != null
                        ? TextButton.icon(
                            onPressed: () { pager.hasMore = true; _loadMore(pager, identical(pager, _all) ? null : _activeFolder); },
                            icon: const Icon(Icons.refresh_rounded), label: const Text('Couldn\'t load more — retry'))
                        : pager.hasMore ? const SizedBox.shrink() : (files.isNotEmpty ? Text('${files.length} files', style: TextStyle(fontSize: 11, color: context.mutedColor)) : const SizedBox.shrink()),
              ),
            ),
          ),
      ],
    );
  }

  Widget _folderTile(BuildContext context, Rec f) {
    final count = f['file_count'] ?? f['files_count'] ?? f['media_count'] ?? 0;
    return InkWell(
      onTap: () => _openFolder(f),
      onLongPress: () => _showFolderMenu(context, f),
      child: Column(
        children: [
          const Icon(Icons.folder_rounded, color: AppPalette.warning, size: 52),
          const SizedBox(height: 8),
          Text(str(f['name'], 'Folder'), maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          Text('$count file${count == 1 ? '' : 's'}', style: TextStyle(fontSize: 10, color: context.mutedColor)),
        ],
      ),
    );
  }

  Widget _fileTile(BuildContext context, Rec m) {
    final mime = '${m['mime_type'] ?? m['type'] ?? m['extension'] ?? ''}'.toLowerCase();
    final url = str(m['url'], '');
    final name = str(m['display_name'] ?? m['name'] ?? m['original_name'] ?? m['filename'], 'File');
    return InkWell(
      onTap: () => _showFileMenu(context, m),
      onLongPress: () => _showFileMenu(context, m),
      child: Column(
        children: [
          _fileAvatar(mime, url),
          const SizedBox(height: 8),
          Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          Text(_size(m['size'] ?? m['file_size']), style: TextStyle(fontSize: 10, color: context.mutedColor)),
        ],
      ),
    );
  }

  Widget _fileAvatar(String mime, String url) {
    if (mime.contains('image') && url.isNotEmpty) {
      return Image.network(url, width: 52, height: 52, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.image_rounded, color: AppPalette.info, size: 52));
    }
    final (icon, color) = switch (mime) {
      final t when t.contains('video') => (Icons.videocam_rounded, AppPalette.accent),
      final t when t.contains('audio') => (Icons.audiotrack_rounded, AppPalette.success),
      final t when t.contains('pdf') => (Icons.picture_as_pdf_rounded, AppPalette.danger),
      final t when t.contains('image') => (Icons.image_rounded, AppPalette.info),
      _ => (Icons.insert_drive_file_rounded, AppPalette.muted),
    };
    return Icon(icon, color: color, size: 52);
  }

  void _showAddMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.upload_rounded),
              title: Text(_activeFolder != null ? 'Upload to "${str(_activeFolder!['name'])}"' : 'Upload file'),
              onTap: () async {
                Navigator.pop(ctx);
                final ok = await pickAndUploadMedia(context, folderId: (_activeFolder?['id'] as num?)?.toInt());
                if (ok) _refreshAll();
              },
            ),
            ListTile(
              leading: const Icon(Icons.create_new_folder_rounded),
              title: const Text('New folder'),
              onTap: () async {
                Navigator.pop(ctx);
                final data = <String, dynamic>{};
                final ok = await showFormSheet(
                  context,
                  title: 'New folder',
                  submitLabel: 'Create',
                  fields: (c) => [
                    FText(label: 'Folder name', required: true, onSaved: (v) => data['name'] = v),
                  ],
                  onSubmit: () => Api.post('/media-library/folders', data: data),
                );
                if (ok) _loadFolders();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showFolderMenu(BuildContext context, Rec f) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: Text(str(f['name']), style: const TextStyle(fontWeight: FontWeight.w700)), subtitle: const Text('Folder')),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.folder_open_rounded),
              title: const Text('Open'),
              onTap: () { Navigator.pop(ctx); _openFolder(f); },
            ),
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline_rounded),
              title: const Text('Rename'),
              onTap: () async {
                Navigator.pop(ctx);
                final data = <String, dynamic>{};
                final ok = await showFormSheet(
                  context,
                  title: 'Rename folder',
                  submitLabel: 'Rename',
                  fields: (c) => [
                    FText(label: 'Name', required: true, initial: str(f['name']), onSaved: (v) => data['name'] = v),
                  ],
                  onSubmit: () => Api.patch('/media-library/folders/${f['id']}', data: data),
                );
                if (ok) _loadFolders();
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_rounded, color: AppPalette.danger),
              title: const Text('Delete', style: TextStyle(color: AppPalette.danger)),
              onTap: () async {
                Navigator.pop(ctx);
                if (!await confirm(context, title: 'Delete folder?', message: 'Files inside will be moved to uncategorised.', destructive: true, confirmLabel: 'Delete')) {
                  return;
                }
                final ok = await runAction(context, () => Api.delete('/media-library/folders/${f['id']}'), success: 'Deleted');
                if (ok) {
                  if (_path.any((p) => p['id'] == f['id'])) _goToRoot();
                  _refreshAll();
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showFileMenu(BuildContext context, Rec m) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(str(m['display_name'] ?? m['name'] ?? m['original_name'], 'File'), style: const TextStyle(fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text('${str(m['mime_type'] ?? m['type'] ?? m['extension'])} · ${_size(m['size'] ?? m['file_size'])}'),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline_rounded),
              title: const Text('Rename'),
              onTap: () async {
                Navigator.pop(ctx);
                final data = <String, dynamic>{};
                final ok = await showFormSheet(
                  context,
                  title: 'Rename file',
                  submitLabel: 'Rename',
                  fields: (c) => [
                    FText(label: 'Name', required: true, initial: str(m['name'] ?? m['display_name']), onSaved: (v) => data['name'] = v),
                  ],
                  onSubmit: () => Api.patch('/media-library/${m['id']}/rename', data: data),
                );
                if (ok) _loadFiles();
              },
            ),
            ListTile(
              leading: const Icon(Icons.file_copy_outlined),
              title: const Text('Copy to folder'),
              onTap: () async {
                Navigator.pop(ctx);
                await _copyOrMoveFile(context, m, copy: true);
              },
            ),
            ListTile(
              leading: const Icon(Icons.drive_file_move_outlined),
              title: const Text('Move to folder'),
              onTap: () async {
                Navigator.pop(ctx);
                await _copyOrMoveFile(context, m, copy: false);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_rounded, color: AppPalette.danger),
              title: const Text('Delete', style: TextStyle(color: AppPalette.danger)),
              onTap: () async {
                Navigator.pop(ctx);
                if (!await confirm(context, title: 'Delete file?', destructive: true, confirmLabel: 'Delete')) return;
                final ok = await runAction(context, () => Api.delete('/media-library/${m['id']}'), success: 'Deleted');
                if (ok) _refreshAll();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _copyOrMoveFile(BuildContext context, Rec m, {required bool copy}) async {
    final target = await showModalBottomSheet<_FolderChoice>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        expand: false,
        builder: (ctx, scrollCtrl) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Align(alignment: Alignment.centerLeft, child: Text(copy ? 'Copy to folder' : 'Move to folder', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
            ),
            Expanded(
              child: ListView(
                controller: scrollCtrl,
                children: [
                  ListTile(
                    leading: const Icon(Icons.folder_open_rounded, color: AppPalette.muted),
                    title: const Text('Uncategorised'),
                    onTap: () => Navigator.pop(ctx, const _FolderChoice(null)),
                  ),
                  for (final f in _folders)
                    ListTile(
                      leading: const Icon(Icons.folder_rounded, color: AppPalette.warning),
                      title: Text(str(f['name'])),
                      onTap: () => Navigator.pop(ctx, _FolderChoice((f['id'] as num).toInt())),
                    ),
                  if (_folders.isEmpty)
                    Padding(padding: const EdgeInsets.all(20), child: Center(child: Text('No folders yet — create one first.', style: TextStyle(color: context.mutedColor)))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (target == null) return;
    final ok = copy
        ? await runAction(context, () => Api.post('/media-library/${m['id']}/copy', data: {'folder_id': target.folderId}), success: 'Copied')
        : await runAction(context, () => Api.patch('/media-library/${m['id']}/move', data: {'folder_id': target.folderId}), success: 'Moved');
    if (ok) _refreshAll();
  }

  String _size(Object? bytes) {
    final b = num.tryParse('${bytes ?? 0}') ?? 0;
    if (b >= 1e9) return '${(b / 1e9).toStringAsFixed(1)} GB';
    if (b >= 1e6) return '${(b / 1e6).toStringAsFixed(1)} MB';
    if (b >= 1e3) return '${(b / 1e3).toStringAsFixed(0)} KB';
    return '$b B';
  }
}

class _FolderChoice {
  const _FolderChoice(this.folderId);
  final int? folderId;
}
