// ignore_for_file: use_build_context_synchronously
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:unichat_mobile_app/features/modules/module_providers.dart";
import "package:unichat_mobile_app/features/modules/_shared.dart";

// ══════════════════════════ Segments ══════════════════════════

class SegmentsPage extends ConsumerWidget {
  const SegmentsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Segments')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addSegment(context, ref),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New segment'),
      ),
      body: ProviderList(
        provider: crmSegmentsProvider,
        emptyLabel: 'No segments yet',
        emptyIcon: Icons.filter_alt_outlined,
        tile: (context, s) => RecordCard(
          title: str(s['name']),
          subtitle: '${s['contact_count'] ?? 0} contacts${s['description'] != null ? ' · ${s['description']}' : ''}',
          leadingIcon: Icons.filter_alt_rounded,
          trailing: RowMenu(items: [
            ('Delete', Icons.delete_outline_rounded, () async {
              final ok = await confirm(context, title: 'Delete "${s['name']}"?', destructive: true, confirmLabel: 'Delete');
              if (!ok) return;
              final done = await runAction(context, () => Api.delete('/crm/segments/${s['id']}'), success: 'Deleted');
              if (done) ref.invalidate(crmSegmentsProvider);
            }),
          ]),
        ),
      ),
    );
  }

  Future<void> _addSegment(BuildContext context, WidgetRef ref) async {
    final filters = <String, dynamic>{};
    final data = <String, dynamic>{};

    final ok = await showFormSheet(
      context,
      title: 'New segment',
      fields: (ctx) => [
        FText(label: 'Name', required: true, onSaved: (v) => data['name'] = v),
        FText(label: 'Description', onSaved: (v) => v.isEmpty ? null : data['description'] = v),
        FSelect<String>(label: 'Lead stage (optional)',
            options: const ['new', 'contacted', 'follow_up', 'enrolled', 'lost'],
            onSaved: (v) => v == null ? null : filters['lead_stage'] = v),
        FNumber(label: 'Min lead score', onSaved: (v) => v == null ? null : filters['score_min'] = v),
        FSelect<String>(label: 'Opted in?', options: const ['yes', 'no'],
            onSaved: (v) => v == null ? null : filters['opted_in'] = v == 'yes'),
        FNumber(label: 'Inactive for (days, optional)', onSaved: (v) => v == null ? null : filters['last_message_days'] = v),
      ],
      onSubmit: () {
        data['filters'] = filters;
        return Api.post('/crm/segments', data: data);
      },
    );
    if (ok) ref.invalidate(crmSegmentsProvider);
  }
}

