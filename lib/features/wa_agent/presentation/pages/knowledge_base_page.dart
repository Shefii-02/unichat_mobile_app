// ignore_for_file: use_build_context_synchronously
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:unichat_mobile_app/features/modules/module_providers.dart";
import "package:unichat_mobile_app/features/modules/_shared.dart";

// ══════════════════════════ Knowledge Base ══════════════════════════

class KnowledgeBasePage extends ConsumerWidget {
  const KnowledgeBasePage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Knowledge Base')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _add(context, ref),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add content'),
      ),
      body: ProviderList(
        provider: knowledgeBaseProvider,
        emptyLabel: 'No documents added',
        emptyIcon: Icons.menu_book_rounded,
        tile: (context, k) => RecordCard(
          title: str(k['name'] ?? k['title'] ?? k['filename'], 'Document'),
          subtitle:
              '${str(k['document_type'] ?? k['type'])} · ${when(k['created_at'])}',
          leadingIcon: switch ('${k['document_type'] ?? k['type'] ?? ''}'.toLowerCase()) {
            final t when t.contains('url') => Icons.link_rounded,
            final t when t.contains('file') => Icons.description_rounded,
            _ => Icons.article_rounded,
          },
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              StatusPill(str(k['status'], 'ready')),
              RowMenu(items: [
                (
                  'Reprocess',
                  Icons.sync_rounded,
                  () async {
                    final ok = await runAction(context,
                        () => Api.post('/wa-agent/knowledge-base/${k['id']}/reprocess'),
                        success: 'Reprocessing');
                    if (ok) ref.invalidate(knowledgeBaseProvider);
                  }
                ),
                (
                  'Delete',
                  Icons.delete_rounded,
                  () async {
                    if (!await confirm(context,
                        title: 'Delete document?',
                        destructive: true,
                        confirmLabel: 'Delete')) { return; }
                    final ok = await runAction(context,
                        () => Api.delete('/wa-agent/knowledge-base/${k['id']}'),
                        success: 'Deleted');
                    if (ok) ref.invalidate(knowledgeBaseProvider);
                  }
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final data = <String, dynamic>{'document_type': 'text'};
    String type = 'text';
    final ok = await showFormSheet(
      context,
      title: 'Add knowledge',
      submitLabel: 'Add',
      fields: (ctx) => [
        FText(
          label: 'Name',
          required: true,
          onSaved: (v) => data['name'] = v,
        ),
        FSelect<String>(
          label: 'Type',
          options: const ['text', 'url'],
          initial: 'text',
          onSaved: (v) {
            type = v ?? 'text';
            data['document_type'] = type;
          },
        ),
        FText(
          label: 'Text content',
          hint: 'Used when type = text',
          maxLines: 6,
          onSaved: (v) => v.isEmpty ? null : data['raw_content'] = v,
        ),
        FText(
          label: 'Source URL',
          hint: 'Used when type = url',
          keyboardType: TextInputType.url,
          onSaved: (v) => v.isEmpty ? null : data['source_url'] = v,
        ),
        FText(
          label: 'Description (optional)',
          maxLines: 2,
          onSaved: (v) => v.isEmpty ? null : data['description'] = v,
        ),
      ],
      onSubmit: () => Api.post('/wa-agent/knowledge-base', data: data),
    );
    if (ok) ref.invalidate(knowledgeBaseProvider);
  }
}

