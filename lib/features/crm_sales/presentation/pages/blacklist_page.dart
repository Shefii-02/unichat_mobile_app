// ignore_for_file: use_build_context_synchronously
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:unichat_mobile_app/features/modules/module_providers.dart";
import "package:unichat_mobile_app/features/modules/_shared.dart";

// ══════════════════════════ Blacklist ══════════════════════════

class BlacklistPage extends ConsumerWidget {
  const BlacklistPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Blacklist')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addNumber(context, ref),
        icon: const Icon(Icons.block_rounded),
        label: const Text('Block number'),
      ),
      body: ProviderList(
        provider: blacklistProvider,
        emptyLabel: 'No blocked numbers',
        emptyIcon: Icons.block_flipped,
        tile: (context, b) => RecordCard(
          title: str(b['phone']),
          subtitle: str(b['reason'], ''),
          leadingIcon: Icons.phone_disabled_rounded,
          leadingColor: AppPalette.danger,
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline_rounded, size: 18),
            onPressed: () async {
              final ok = await confirm(context, title: 'Unblock ${b['phone']}?', confirmLabel: 'Unblock');
              if (!ok) return;
              final done = await runAction(context, () => Api.delete('/blacklist/${b['id']}'), success: 'Removed');
              if (done) ref.invalidate(blacklistProvider);
            },
          ),
        ),
      ),
    );
  }

  Future<void> _addNumber(BuildContext context, WidgetRef ref) async {
    final data = <String, dynamic>{};
    final ok = await showFormSheet(
      context,
      title: 'Block a number',
      submitLabel: 'Block',
      fields: (ctx) => [
        FText(label: 'Phone number', required: true, keyboardType: TextInputType.phone, onSaved: (v) => data['phone'] = v),
        FText(label: 'Reason', onSaved: (v) => v.isEmpty ? null : data['reason'] = v),
      ],
      onSubmit: () => Api.post('/blacklist', data: data),
    );
    if (ok) ref.invalidate(blacklistProvider);
  }
}
