import 'package:file_picker/file_picker.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:unichat_mobile_app/features/modules/_shared.dart';

const _categories = {
  'identity': 'Identity proof',
  'address': 'Address proof',
  'education': 'Education',
  'experience': 'Experience',
  'contract': 'Contract / offer',
  'other': 'Other',
};

/// My documents — ID proof, certificates, contracts. Private to the signed-in user (GET/POST/DELETE hr/documents/me).
class DocumentsPage extends StatefulWidget {
  const DocumentsPage({super.key});
  @override
  State<DocumentsPage> createState() => _DocumentsPageState();
}

class _DocumentsPageState extends State<DocumentsPage> {
  List<Map<String, dynamic>> _docs = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await Api.list('/hr/documents/me');
      if (mounted) setState(() => _docs = rows);
    } catch (e) {
      if (mounted) setState(() => _error = apiErrorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _add() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'webp', 'doc', 'docx'],
    );
    final file = picked?.files.single;
    if (file == null || file.path == null || !mounted) return;
    final title = TextEditingController(
      text: file.name.replaceAll(RegExp(r'\.[^.]+$'), ''),
    );
    var category = 'identity';
    final ok = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => StatefulBuilder(
            builder:
                (ctx, setD) => AlertDialog(
                  title: const Text('Add document'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: title,
                        decoration: const InputDecoration(labelText: 'Title'),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: category,
                        decoration: const InputDecoration(labelText: 'Type'),
                        items: [
                          for (final e in _categories.entries)
                            DropdownMenuItem(
                              value: e.key,
                              child: Text(e.value),
                            ),
                        ],
                        onChanged: (v) => setD(() => category = v ?? category),
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Upload'),
                    ),
                  ],
                ),
          ),
    );
    if (ok != true || !mounted) return;
    final done = await runAction(context, () async {
      await Api.raw.post(
        '/hr/documents/me',
        data: FormData.fromMap({
          'title': title.text.trim().isEmpty ? file.name : title.text.trim(),
          'category': category,
          'file': await MultipartFile.fromFile(file.path!, filename: file.name),
        }),
      );
    }, success: 'Document added.');
    if (done) _load();
  }

  Future<void> _delete(Map<String, dynamic> d) async {
    final yes = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Delete document?'),
            content: Text('"${d['title']}" will be removed.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Delete'),
              ),
            ],
          ),
    );
    if (yes != true || !mounted) return;
    final done = await runAction(
      context,
      () => Api.delete('/hr/documents/me/${d['id']}'),
      success: 'Deleted.',
    );
    if (done) _load();
  }

  String _size(num b) =>
      b >= 1048576
          ? '${(b / 1048576).toStringAsFixed(1)} MB'
          : '${(b / 1024).ceil()} KB';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Documents')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.upload_file_rounded),
        label: const Text('Add'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child:
            _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? ListView(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(_error!),
                    ),
                  ],
                )
                : _docs.isEmpty
                ? ListView(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(40),
                      child: Column(
                        children: [
                          Icon(
                            Icons.folder_open_rounded,
                            size: 48,
                            color: context.mutedColor,
                          ),
                          const SizedBox(height: 12),
                          const Text('No documents yet'),
                          const SizedBox(height: 4),
                          Text(
                            'Add your ID proof, certificates or contract.',
                            style: TextStyle(
                              fontSize: 12,
                              color: context.mutedColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                )
                : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                  itemCount: _docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final d = _docs[i];
                    final image = (d['mime'] ?? '').toString().startsWith(
                      'image/',
                    );
                    return Container(
                      decoration: BoxDecoration(
                        color: context.altSurface,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListTile(
                        leading: Icon(
                          image
                              ? Icons.image_outlined
                              : Icons.description_outlined,
                        ),
                        title: Text(
                          '${d['title']}',
                          style: const TextStyle(fontSize: 14),
                        ),
                        subtitle: Text(
                          '${_categories[d['category']] ?? 'Other'} · ${_size((d['size'] ?? 0) as num)} · ${when(d['created_at'])}',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: context.mutedColor,
                          ),
                        ),
                        onTap:
                            () => launchUrl(
                              Uri.parse('${d['url']}'),
                              mode: LaunchMode.externalApplication,
                            ),
                        trailing: IconButton(
                          icon: const Icon(
                            Icons.delete_outline_rounded,
                            size: 20,
                          ),
                          onPressed: () => _delete(d),
                        ),
                      ),
                    );
                  },
                ),
      ),
    );
  }
}
