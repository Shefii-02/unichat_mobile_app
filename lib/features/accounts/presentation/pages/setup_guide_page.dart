// ignore_for_file: use_build_context_synchronously
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:unichat_mobile_app/core/permissions/permission_guard.dart";
import "package:unichat_mobile_app/core/storage/local_storage.dart";
import "package:unichat_mobile_app/core/widgets/app_empty_state.dart";
import "package:unichat_mobile_app/features/modules/module_providers.dart";
import "package:unichat_mobile_app/features/modules/_shared.dart";

// ══════════════════════════ Setup Guide ══════════════════════════

class SetupGuidePage extends ConsumerWidget {
  const SetupGuidePage({super.key});

  static const _steps = <(String, String, String, IconData)>[
    ('session_connected', 'Connect WhatsApp', 'Scan the QR to link your number', Icons.qr_code_rounded),
    ('phone_added', 'Add a phone number', 'Register the number campaigns send from', Icons.smartphone_rounded),
    ('templates_created', 'Create a message template', 'Approved templates unlock broadcasts', Icons.dashboard_customize_rounded),
    ('kb_added', 'Add knowledge base content', 'Teach the AI agent about your business', Icons.menu_book_rounded),
    ('agent_configured', 'Configure the AI agent', 'Set tone, playbook and routing', Icons.smart_toy_rounded),
    ('listings_added', 'Add listings / products', 'The agent matches leads to these', Icons.inventory_2_rounded),
    ('google_connected', 'Connect Google', 'Sync leads to Sheets, store files in Drive', Icons.add_to_drive_rounded),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Setup Guide')),
      body: ProviderObject(
        provider: setupStatusProvider,
        builder: (context, status) {
          final done = _steps.where((s) => status[s.$1] == true).length;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$done of ${_steps.length} complete',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: _steps.isEmpty ? 0 : done / _steps.length,
                  minHeight: 8,
                ),
              ),
              const SizedBox(height: 16),
              ..._steps.map((s) {
                final complete = status[s.$1] == true;
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: Icon(
                      complete
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked_rounded,
                      color: complete
                          ? AppPalette.success
                          : context.mutedColor,
                    ),
                    title: Text(s.$2,
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            decoration: complete
                                ? TextDecoration.lineThrough
                                : null)),
                    subtitle: Text(s.$3),
                    trailing: Icon(s.$4, color: context.mutedColor, size: 20),
                  ),
                );
              }),
            ],
          );
        },
      ),
    );
  }
}

