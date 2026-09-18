// WA Agents' "Catalog" quick link — mirrors frontend/src/pages/wa-agent/catalog/CatalogPage.tsx.
// The live listings (properties / clinic services / courses / products, depending on the
// company's chosen industry template) that the AI agent answers about and matches leads
// against. Google Drive media storage is intentionally left out of this port — media is
// added by URL only, which still covers the full `media: [{url}]` data model.
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:unichat_mobile_app/features/modules/_shared.dart';
import 'package:unichat_mobile_app/features/wa_agent/presentation/pages/wa_agent_listing_editor_page.dart';

const _statusColors = {
  'active': AppPalette.success,
  'sold': AppPalette.danger,
  'draft': AppPalette.warning,
  'inactive': AppPalette.muted,
};

class WaAgentCatalogPage extends StatefulWidget {
  const WaAgentCatalogPage({super.key});
  @override
  State<WaAgentCatalogPage> createState() => _WaAgentCatalogPageState();
}

class _WaAgentCatalogPageState extends State<WaAgentCatalogPage> {
  Map<String, Rec> _templates = {};
  String _activeKey = 'generic';
  List<Rec> _listings = [];
  bool _loading = true;
  bool _exporting = false;
  bool _importing = false;

  Rec? get _template => _templates[_activeKey];
  String get _listingType => str(_template?['listing_type'], 'product');
  List<Rec> get _shown => _listings.where((l) => str(l['type']) == _listingType).toList();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final tRes = await Api.one('/listings/templates');
      final lRes = await Api.list('/listings');
      if (mounted) {
        setState(() {
          _templates = (tRes['templates'] as Map?)?.map((k, v) => MapEntry('$k', (v as Map).cast<String, dynamic>())) ?? {};
          _activeKey = str(tRes['active'], 'generic');
          _listings = lRes;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
      }
    }
  }

  Future<void> _openEditor({Rec? existing}) async {
    final changed = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => WaAgentListingEditorPage(listingType: _listingType, template: _template, existing: existing),
    ));
    if (changed == true) _load();
  }

  Future<void> _delete(Rec l) async {
    if (!await confirm(context, title: 'Delete listing?', message: 'The AI will no longer surface it.', destructive: true, confirmLabel: 'Delete')) {
      return;
    }
    final ok = await runAction(context, () => Api.delete('/listings/${l['id']}'), success: 'Deleted');
    if (ok) _load();
  }

  Future<void> _exportCsv() async {
    setState(() => _exporting = true);
    try {
      final res = await Api.raw.get('/listings/export', queryParameters: {'type': _listingType}, options: Options(responseType: ResponseType.bytes));
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/${_listingType}s-${DateTime.now().millisecondsSinceEpoch}.csv');
      await file.writeAsBytes(res.data as List<int>);
      if (mounted) await Share.shareXFiles([XFile(file.path)], text: '${_listingType}s export');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _importCsv() async {
    final picked = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['csv', 'txt']);
    final path = picked?.files.single.path;
    if (path == null) return;
    setState(() => _importing = true);
    try {
      final form = FormData.fromMap({'file': await MultipartFile.fromFile(path, filename: picked!.files.single.name)});
      final res = await Api.raw.post('/listings/import', data: form);
      final body = (res.data as Map).cast<String, dynamic>();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(str(body['message'], 'Import finished.'))));
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Listings & Products'),
        actions: [
          IconButton(
            tooltip: 'Import CSV',
            onPressed: _importing ? null : _importCsv,
            icon: _importing ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.upload_file_rounded),
          ),
          IconButton(
            tooltip: 'Export CSV',
            onPressed: (_exporting || _shown.isEmpty) ? null : _exportCsv,
            icon: _exporting ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.download_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.add_rounded),
        label: Text('Add $_listingType'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  Text('The live catalog your AI agent uses to answer queries and match leads', style: TextStyle(fontSize: 12, color: context.mutedColor)),
                  if (_template != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: context.altSurface, borderRadius: BorderRadius.circular(10)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${str(_template!['name'])} template', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                          const SizedBox(height: 4),
                          Text(
                            'The agent asks: ${((_template!['question_flow'] as List?) ?? []).take(3).join(' → ')}…',
                            style: TextStyle(fontSize: 11, color: context.mutedColor),
                          ),
                          Text(
                            'Qualifies a lead once it has: ${((_template!['qualification_fields'] as List?) ?? []).where((f) => (f as Map)['required'] == true).map((f) => str((f as Map)['label'])).join(', ')}.',
                            style: TextStyle(fontSize: 11, color: context.mutedColor),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  if (_shown.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 40),
                      child: Column(children: [
                        Icon(Icons.inventory_2_outlined, size: 40, color: context.mutedColor.withValues(alpha: 0.4)),
                        const SizedBox(height: 10),
                        Text('No ${_listingType}s yet', style: const TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        Text('Add your catalog so the AI can answer accurately.', style: TextStyle(fontSize: 12, color: context.mutedColor)),
                      ]),
                    )
                  else
                    ..._shown.map(_listingCard),
                ],
              ),
            ),
    );
  }

  Widget _listingCard(Rec l) {
    final media = (l['media'] as List?) ?? [];
    final thumbUrl = media.isNotEmpty ? str((media.first as Map)['url'], '') : '';
    final attrs = (l['attributes'] as Map?) ?? {};
    final customFields = (l['custom_fields'] as List?) ?? [];
    final status = str(l['status'], 'active');
    final price = l['price'];
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(border: Border.all(color: context.lineColor), borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () => _openEditor(existing: l),
        onLongPress: () => _showMenu(l),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (thumbUrl.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(thumbUrl, width: 64, height: 64, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(width: 64, height: 64, color: context.altSurface)),
              )
            else
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(color: context.altSurface, borderRadius: BorderRadius.circular(8)),
                child: Icon(Icons.inventory_2_outlined, color: context.mutedColor),
              ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(child: Text(str(l['title']), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14))),
                    StatusPill(status, color: _statusColors[status] ?? AppPalette.muted),
                  ]),
                  if (str(l['location'], '').isNotEmpty)
                    Padding(padding: const EdgeInsets.only(top: 2), child: Text(str(l['location']), style: TextStyle(fontSize: 11, color: context.mutedColor))),
                  if (price != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        '$price ${str(l['currency'], 'INR')}${str(l['price_unit'], '').isNotEmpty ? ' · ${l['price_unit']}' : ''}',
                        style: const TextStyle(fontSize: 12, color: AppPalette.accent, fontWeight: FontWeight.w600),
                      ),
                    ),
                  if (attrs.isNotEmpty || customFields.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Wrap(spacing: 4, runSpacing: 4, children: [
                        for (final e in attrs.entries.take(4))
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(color: context.altSurface, borderRadius: BorderRadius.circular(4)),
                            child: Text('${e.key}: ${e.value}', style: const TextStyle(fontSize: 10)),
                          ),
                        for (final f in customFields.take(4))
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(color: AppPalette.accent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                            child: Text('${(f as Map)['key']}: ${f['value']}', style: const TextStyle(fontSize: 10, color: AppPalette.accent)),
                          ),
                      ]),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showMenu(Rec l) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.edit_rounded), title: const Text('Edit'), onTap: () { Navigator.pop(ctx); _openEditor(existing: l); }),
          ListTile(
            leading: const Icon(Icons.delete_rounded, color: AppPalette.danger),
            title: const Text('Delete', style: TextStyle(color: AppPalette.danger)),
            onTap: () { Navigator.pop(ctx); _delete(l); },
          ),
        ]),
      ),
    );
  }
}
