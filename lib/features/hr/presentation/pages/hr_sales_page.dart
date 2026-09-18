// ignore_for_file: use_build_context_synchronously
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:unichat_mobile_app/features/modules/module_providers.dart";
import "package:unichat_mobile_app/features/modules/_shared.dart";

/// Split out of the former shared `HrAdminPage` (tab 3, "Sales").
class HrSalesPage extends ConsumerWidget {
  const HrSalesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(hrSalesSummaryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Sales')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _recordSale(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Record sale'),
      ),
      body: Column(
      children: [
        summaryAsync.maybeWhen(
          orElse: () => const SizedBox.shrink(),
          data: (res) {
            final rows = (res['data'] is List) ? (res['data'] as List).whereType<Map>().toList() : const <Map>[];
            if (rows.isEmpty) return const SizedBox.shrink();
            return SizedBox(
              height: 96,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.all(12),
                itemCount: rows.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final r = rows[i];
                  final progress = r['progress'];
                  return Container(
                    width: 140,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      border: Border.all(color: context.lineColor),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(str(r['staff_name']), maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
                        const Spacer(),
                        Text(money(r['sold_total']), style: const TextStyle(fontWeight: FontWeight.w800)),
                        Text(progress != null ? '$progress% of target' : 'No target set',
                            style: TextStyle(fontSize: 10.5, color: context.mutedColor)),
                      ],
                    ),
                  );
                },
              ),
            );
          },
        ),
        const Divider(height: 1),
        Expanded(
          child: ProviderList(
            provider: hrSalesAdminProvider,
            emptyLabel: 'No sales recorded',
            emptyIcon: Icons.point_of_sale_rounded,
            tile: (context, s) {
              final staff = (s['staff'] is Map) ? (s['staff'] as Map) : const {};
              final listing = (s['listing'] is Map) ? (s['listing'] as Map) : const {};
              return RecordCard(
                title: str(listing['title'] ?? s['item_label'], 'Sale'),
                subtitle: '${str(staff['name'])} · ${when(s['sold_at'])}',
                leadingIcon: Icons.point_of_sale_rounded,
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(money(s['amount']), style: const TextStyle(fontWeight: FontWeight.w700)),
                  RowMenu(items: [
                    ('Void', Icons.undo_rounded, () async {
                      final sure = await confirm(context, title: 'Void this sale?', destructive: true, confirmLabel: 'Void');
                      if (!sure) return;
                      final ok = await runAction(context, () => Api.delete('/hr/sales/${s['id']}'), success: 'Voided');
                      if (ok) ref.invalidate(hrSalesAdminProvider);
                    }),
                  ]),
                ]),
              );
            },
          ),
        ),
      ],
      ),
    );
  }
}

Future<void> _recordSale(BuildContext context) async {
  List<Rec> staff;
  List<Rec> listings;
  try {
    staff = await Api.list('/staff');
    listings = await Api.list('/listings');
  } catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
    return;
  }
  if (!context.mounted) return;

  final data = <String, dynamic>{'sold_at': DateTime.now().toIso8601String()};
  final ok = await showFormSheet(
    context,
    title: 'Record sale',
    submitLabel: 'Record',
    fields: (ctx) => [
      FSelect<Rec>(label: 'Staff', options: staff, labelOf: (s) => str(s['name']), onSaved: (s) => data['staff_id'] = s?['id']),
      if (listings.isNotEmpty)
        FSelect<Rec>(label: 'Catalog item (optional)', options: listings, labelOf: (l) => str(l['title']),
            onSaved: (l) => data['listing_id'] = l?['id']),
      FText(label: 'Item name (if not from catalog)', onSaved: (v) => v.isEmpty ? null : data['item_label'] = v),
      FNumber(label: 'Amount', required: true, onSaved: (v) => data['amount'] = v),
      FText(label: 'Note', onSaved: (v) => v.isEmpty ? null : data['note'] = v),
    ],
    onSubmit: () => Api.post('/hr/sales', data: data),
  );
  if (ok && context.mounted) {
    ProviderScope.containerOf(context, listen: false)
      ..invalidate(hrSalesAdminProvider)
      ..invalidate(hrSalesSummaryProvider);
  }
}

