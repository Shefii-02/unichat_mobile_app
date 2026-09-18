// ignore_for_file: use_build_context_synchronously
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:image_picker/image_picker.dart";
import "package:url_launcher/url_launcher.dart";
import "package:dio/dio.dart";
import "package:unichat_mobile_app/core/permissions/permission_guard.dart";
import "package:unichat_mobile_app/features/modules/module_providers.dart";
import "package:unichat_mobile_app/features/modules/_shared.dart";

// ══════════════════════════ Survey Forms ══════════════════════════

class SurveyFormsPage extends ConsumerWidget {
  const SurveyFormsPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Survey Forms')),
      body: ProviderList(
        provider: surveyFormsProvider,
        emptyLabel: 'No forms yet',
        emptyIcon: Icons.assignment_rounded,
        tile: (context, f) {
          final active = f['is_active'] == true ||
              f['active'] == true ||
              f['status'] == 'published';
          return RecordCard(
            title: str(f['name'] ?? f['title']),
            subtitle:
                '${str(f['fields_count'] ?? (f['fields'] is List ? (f['fields'] as List).length : ''), '0')} fields · ${str(f['responses_count'] ?? f['submissions_count'] ?? '0')} responses',
            leadingIcon: Icons.assignment_rounded,
            onTap: () => _responses(context, f),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                StatusPill(active ? 'active' : 'draft'),
                RowMenu(items: [
                  ('View responses', Icons.list_alt_rounded,
                      () => _responses(context, f)),
                  (
                    active ? 'Deactivate' : 'Activate',
                    Icons.toggle_on_rounded,
                    () async {
                      final ok = await runAction(
                        context,
                        () => Api.put('/survey-forms/${f['id']}', data: {
                          'name': str(f['name'] ?? f['title']),
                          'fields': f['fields'] ?? [],
                          'is_active': !active,
                        }),
                        success: 'Updated',
                      );
                      if (ok) ref.invalidate(surveyFormsProvider);
                    }
                  ),
                  (
                    'Delete',
                    Icons.delete_rounded,
                    () async {
                      if (!await confirm(context,
                          title: 'Delete form?',
                          destructive: true,
                          confirmLabel: 'Delete')) { return; }
                      final ok = await runAction(context,
                          () => Api.delete('/survey-forms/${f['id']}'),
                          success: 'Deleted');
                      if (ok) ref.invalidate(surveyFormsProvider);
                    }
                  ),
                ]),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _responses(BuildContext context, Rec f) async {
    List<Rec> rows;
    try {
      rows = await Api.list('/survey-forms/${f['id']}/responses');
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
      }
      return;
    }
    if (!context.mounted) return;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (ctx, sc) => ListView(
          controller: sc,
          padding: const EdgeInsets.all(20),
          children: [
            Text('${str(f['name'] ?? f['title'])} — ${rows.length} responses',
                style: Theme.of(ctx)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            if (rows.isEmpty)
              Text('No responses yet',
                  style: TextStyle(color: ctx.mutedColor))
            else
              ...rows.map((r) {
                final answers = r['answers'] ?? r['data'] ?? r;
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(when(r['created_at']),
                            style: TextStyle(
                                color: ctx.mutedColor, fontSize: 11)),
                        const SizedBox(height: 4),
                        if (answers is Map)
                          ...answers.entries.map((e) => Text(
                              '${e.key}: ${e.value}',
                              style: const TextStyle(fontSize: 13))),
                      ],
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}

