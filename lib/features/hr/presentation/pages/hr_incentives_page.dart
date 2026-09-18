// ignore_for_file: use_build_context_synchronously
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:unichat_mobile_app/features/modules/module_providers.dart";
import "package:unichat_mobile_app/features/modules/_shared.dart";

// ══════════════════════════ Incentives (rules + ledger) ══════════════════════════

/// Split out of the former shared `HrAdminPage` (tab 4, "Incentives").
class HrIncentivesPage extends ConsumerWidget {
  const HrIncentivesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Incentives')),
      body: ListView(
      children: [
        SectionHeader('Incentive rules',
            action: TextButton(onPressed: () => _editRule(context, ref, null), child: const Text('+ Add'))),
        ref.watch(hrIncentiveRulesProvider).maybeWhen(
          orElse: () => const SizedBox.shrink(),
          data: (rules) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: rules.map((r) {
                final kind = str(r['kind'], 'percentage');
                final label = kind == 'percentage' ? '${str(r['name'])} · ${r['percent']}%' : '${str(r['name'])} · ${money(r['fixed_amount'])}';
                return InputChip(
                  label: Text(label, style: const TextStyle(fontSize: 11.5)),
                  onPressed: () => _editRule(context, ref, r),
                  onDeleted: () async {
                    final ok = await confirm(context, title: 'Delete rule?', destructive: true, confirmLabel: 'Delete');
                    if (!ok) return;
                    final done = await runAction(context, () => Api.delete('/hr/incentive-rules/${r['id']}'), success: 'Deleted');
                    if (done) ref.invalidate(hrIncentiveRulesProvider);
                  },
                );
              }).toList(),
            ),
          ),
        ),
        const SizedBox(height: 8),
        SectionHeader('Ledger', action: TextButton(onPressed: () => _addIncentive(context, ref), child: const Text('+ Add'))),
        ref.watch(hrIncentivesProvider).maybeWhen(
          orElse: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          ),
          data: (rows) {
            if (rows.isEmpty) {
              return Padding(
                padding: const EdgeInsets.all(24),
                child: Text('No incentives recorded', style: TextStyle(color: context.mutedColor)),
              );
            }
            return Column(
              children: rows.map((i) {
                final user = (i['user'] is Map) ? (i['user'] as Map) : const {};
                return RecordCard(
                  title: '${str(user['name'], 'Staff')} · ${str(i['title'])}',
                  subtitle: when(i['earned_on']),
                  leadingIcon: Icons.card_giftcard_rounded,
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(money(i['amount']), style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(width: 6),
                    StatusPill(str(i['status'], 'pending')),
                  ]),
                );
              }).toList(),
            );
          },
        ),
      ],
      ),
    );
  }

  Future<void> _editRule(BuildContext context, WidgetRef ref, Rec? rule) async {
    final data = <String, dynamic>{};
    final ok = await showFormSheet(
      context,
      title: rule == null ? 'Add incentive rule' : 'Edit incentive rule',
      fields: (ctx) => [
        FText(label: 'Name', initial: rule?['name'] as String?, required: true, onSaved: (v) => data['name'] = v),
        FSelect<String>(label: 'Category', options: const ['service', 'course', 'product', 'other'],
            initial: str(rule?['category'], 'service'), onSaved: (v) => data['category'] = v ?? 'service'),
        FSelect<String>(label: 'Kind', options: const ['percentage', 'fixed'],
            initial: str(rule?['kind'], 'percentage'), onSaved: (v) => data['kind'] = v ?? 'percentage'),
        FNumber(label: 'Percent', initial: rule?['percent'] as num?, onSaved: (v) => data['percent'] = v),
        FNumber(label: 'Fixed amount', initial: rule?['fixed_amount'] as num?, onSaved: (v) => data['fixed_amount'] = v),
      ],
      onSubmit: () => rule == null
          ? Api.post('/hr/incentive-rules', data: data)
          : Api.patch('/hr/incentive-rules/${rule['id']}', data: data),
    );
    if (ok) ref.invalidate(hrIncentiveRulesProvider);
  }

  Future<void> _addIncentive(BuildContext context, WidgetRef ref) async {
    List<Rec> staff;
    try {
      staff = await Api.list('/staff');
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
      return;
    }
    if (!context.mounted) return;
    final data = <String, dynamic>{'earned_on': DateTime.now().toIso8601String()};
    final ok = await showFormSheet(
      context,
      title: 'Add incentive',
      fields: (ctx) => [
        FSelect<Rec>(label: 'Staff', options: staff, labelOf: (s) => str(s['name']), onSaved: (s) => data['user_id'] = s?['id']),
        FText(label: 'Title', required: true, onSaved: (v) => data['title'] = v),
        FNumber(label: 'Amount', onSaved: (v) => data['amount'] = v),
        FText(label: 'Note', onSaved: (v) => v.isEmpty ? null : data['note'] = v),
      ],
      onSubmit: () => Api.post('/hr/incentives', data: data),
    );
    if (ok) ref.invalidate(hrIncentivesProvider);
  }
}

