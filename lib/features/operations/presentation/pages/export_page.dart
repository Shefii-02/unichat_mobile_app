// ignore_for_file: use_build_context_synchronously
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:image_picker/image_picker.dart";
import "package:url_launcher/url_launcher.dart";
import "package:dio/dio.dart";
import "package:unichat_mobile_app/core/permissions/permission_guard.dart";
import "package:unichat_mobile_app/features/modules/module_providers.dart";
import "package:unichat_mobile_app/features/modules/_shared.dart";

// ══════════════════════════ Data Export ══════════════════════════

class ExportPage extends ConsumerWidget {
  const ExportPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Future<void> start(String kind, String path) async {
      final ok = await runAction(context, () => Api.post(path),
          success: '$kind export queued');
      if (ok) ref.invalidate(exportJobsProvider);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Data Export')),
      body: ProviderList(
        provider: exportJobsProvider,
        emptyLabel: 'No export jobs yet',
        emptyIcon: Icons.ios_share_rounded,
        header: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => start('Chats', '/wa-export/chats'),
                icon: const Icon(Icons.forum_rounded, size: 18),
                label: const Text('Chats'),
              ),
              OutlinedButton.icon(
                onPressed: () => start('Contacts', '/wa-export/contacts'),
                icon: const Icon(Icons.contacts_rounded, size: 18),
                label: const Text('Contacts'),
              ),
              OutlinedButton.icon(
                onPressed: () => start('Groups', '/wa-export/groups'),
                icon: const Icon(Icons.groups_rounded, size: 18),
                label: const Text('Groups'),
              ),
            ],
          ),
        ),
        tile: (context, j) {
          final done = '${j['status'] ?? ''}'.toLowerCase() == 'completed';
          return RecordCard(
            title: str(j['type'] ?? j['kind'] ?? j['export_type'], 'Export'),
            subtitle:
                '${str(j['records_count'] ?? j['rows'] ?? '')} rows · ${when(j['created_at'])}',
            leadingIcon: Icons.description_rounded,
            trailing: done
                ? IconButton(
                    icon: const Icon(Icons.download_rounded),
                    onPressed: () => launchUrl(
                      Uri.parse(
                          '${Api.raw.options.baseUrl}/wa-export/${j['id']}/download'),
                      mode: LaunchMode.externalApplication,
                    ),
                  )
                : StatusPill(str(j['status'], 'processing')),
          );
        },
      ),
    );
  }
}

