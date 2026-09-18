// ignore_for_file: use_build_context_synchronously
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:unichat_mobile_app/features/modules/module_providers.dart";
import "package:unichat_mobile_app/features/modules/_shared.dart";

// ══════════════════════════ Deal pipelines (Kanban-lite) ══════════════════════════

const _dealStages = ['new', 'qualified', 'proposal', 'negotiation', 'won', 'lost'];
const _dealStageLabels = {
  'new': 'New', 'qualified': 'Qualified', 'proposal': 'Proposal',
  'negotiation': 'Negotiation', 'won': 'Won', 'lost': 'Lost',
};

class DealsPage extends ConsumerWidget {
  const DealsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(crmDealsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Deal Pipelines')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addDeal(context, ref),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New deal'),
      ),
      body: AsyncView<List<Rec>>(
        value: async,
        onRefresh: () async => ref.invalidate(crmDealsProvider),
        isEmpty: (d) => d.isEmpty,
        emptyLabel: 'No deals yet',
        emptyIcon: Icons.handshake_outlined,
        data: (deals) {
          final byStage = {for (final s in _dealStages) s: deals.where((d) => d['stage'] == s).toList()};
          return ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(12),
            children: _dealStages.map((stage) {
              final rows = byStage[stage] ?? const [];
              final total = rows.fold<num>(0, (sum, d) => sum + (num.tryParse('${d['value']}') ?? 0));
              return Container(
                width: 240,
                margin: const EdgeInsets.only(right: 10),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: context.altSurface, borderRadius: BorderRadius.circular(14)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      child: Row(
                        children: [
                          Text(_dealStageLabels[stage] ?? stage, style: const TextStyle(fontWeight: FontWeight.w700)),
                          const SizedBox(width: 6),
                          Text('(${rows.length})', style: TextStyle(color: context.mutedColor, fontSize: 12)),
                          const Spacer(),
                          Text(money(total), style: TextStyle(color: context.mutedColor, fontSize: 11)),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.separated(
                        itemCount: rows.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          final deal = rows[i];
                          final contact = (deal['contact'] is Map) ? (deal['contact'] as Map) : const {};
                          return Card(
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () => _openDeal(context, ref, deal),
                              child: Padding(
                                padding: const EdgeInsets.all(10),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(str(deal['title']), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                        maxLines: 1, overflow: TextOverflow.ellipsis),
                                    if (contact['name'] != null)
                                      Text(str(contact['name']), style: TextStyle(fontSize: 11.5, color: context.mutedColor)),
                                    const SizedBox(height: 6),
                                    Text(money(deal['value']), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }

  Future<void> _openDeal(BuildContext context, WidgetRef ref, Rec deal) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(str(deal['title']), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 4),
            Text(money(deal['value']), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
            const SizedBox(height: 16),
            const Text('Move to stage', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              children: _dealStages.map((s) {
                final selected = deal['stage'] == s;
                return ChoiceChip(
                  label: Text(_dealStageLabels[s] ?? s),
                  selected: selected,
                  onSelected: (_) async {
                    Navigator.pop(ctx);
                    final ok = await runAction(context, () => Api.patch('/crm/deals/${deal['id']}/stage', data: {'stage': s}),
                        success: 'Moved to ${_dealStageLabels[s]}');
                    if (ok) ref.invalidate(crmDealsProvider);
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () async {
                Navigator.pop(ctx);
                final sure = await confirm(context, title: 'Delete this deal?', destructive: true, confirmLabel: 'Delete');
                if (!sure) return;
                final ok = await runAction(context, () => Api.delete('/crm/deals/${deal['id']}'), success: 'Deleted');
                if (ok) ref.invalidate(crmDealsProvider);
              },
              icon: const Icon(Icons.delete_outline_rounded, color: AppPalette.danger),
              label: const Text('Delete deal', style: TextStyle(color: AppPalette.danger)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addDeal(BuildContext context, WidgetRef ref) async {
    List<Rec> contacts;
    try {
      contacts = await Api.list('/contacts', query: {'per_page': 100});
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
      return;
    }
    if (!context.mounted) return;
    final data = <String, dynamic>{'stage': 'new'};
    final ok = await showFormSheet(
      context,
      title: 'New deal',
      fields: (ctx) => [
        FText(label: 'Title', required: true, onSaved: (v) => data['title'] = v),
        FNumber(label: 'Value', required: true, onSaved: (v) => data['value'] = v),
        if (contacts.isNotEmpty)
          FSelect<Rec>(label: 'Contact (optional)', options: contacts,
              labelOf: (c) => '${c['name'] ?? c['phone']}', onSaved: (c) => data['contact_id'] = c?['id']),
      ],
      onSubmit: () => Api.post('/crm/deals', data: data),
    );
    if (ok) ref.invalidate(crmDealsProvider);
  }
}

