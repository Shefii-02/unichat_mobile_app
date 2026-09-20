import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:unichat_mobile_app/core/constants/app_colors.dart';
import 'package:unichat_mobile_app/core/permissions/permission_guard.dart';
import 'package:unichat_mobile_app/core/widgets/app_avatar.dart';
import 'package:unichat_mobile_app/features/chats/presentation/pages/wa_session_chats_page.dart';
import 'package:unichat_mobile_app/features/modules/_shared.dart';
import 'package:unichat_mobile_app/features/modules/module_providers.dart';

/// WA Chat's "Chats" entry point — a list of this company's WhatsApp sessions. Tapping one
/// pushes [WaSessionChatsPage] showing just that session's chats; the back button returns here
/// to pick a different session. Chats only ever exist *within* one session's account, so this
/// two-step flow (session list -> that session's chats) replaces the old inline session-picker
/// dropdown that sat on top of a single combined page.
class ChatsPage extends ConsumerWidget {
  const ChatsPage({super.key});

  static const _connectedStatuses = {'ready', 'connected', 'working', 'authenticated'};

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!PermissionGuard.can('wa_chat.chats.view')) {
      return Scaffold(
        appBar: AppBar(title: const Text('WA Chats')),
        body: Center(
          child: Text("You don't have access to this section", style: TextStyle(color: context.mutedColor)),
        ),
      );
    }

    final async = ref.watch(wahaSessionsProvider);
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        backgroundColor: AppColors.primaryDark,
        elevation: 0,
        title: const Text('Chats', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text("Couldn't load sessions — ${apiErrorMessage(e)}", textAlign: TextAlign.center, style: TextStyle(color: context.mutedColor)),
          ),
        ),
        data: (sessions) {
          if (sessions.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text('Connect and start a WhatsApp session under Sessions to use Chats.',
                    textAlign: TextAlign.center, style: TextStyle(color: context.mutedColor)),
              ),
            );
          }
          final sorted = [...sessions]..sort((a, b) {
              final aConnected = _connectedStatuses.contains(str(a['status'], '').toLowerCase()) ? 0 : 1;
              final bConnected = _connectedStatuses.contains(str(b['status'], '').toLowerCase()) ? 0 : 1;
              return aConnected - bConnected;
            });
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(wahaSessionsProvider),
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: sorted.length,
              separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade100),
              itemBuilder: (_, i) => _SessionTile(session: sorted[i]),
            ),
          );
        },
      ),
    );
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({required this.session});
  final Rec session;

  static const _connectedStatuses = {'ready', 'connected', 'working', 'authenticated'};

  @override
  Widget build(BuildContext context) {
    final label = str(session['display_name'] ?? session['phone'] ?? session['session_name'], 'Session');
    final phone = str(session['phone'], '');
    final status = str(session['status'], '').toLowerCase();
    final connected = _connectedStatuses.contains(status);
    return Material(
      color: Colors.white,
      child: ListTile(
        leading: AppAvatar(name: label, size: 44),
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
        subtitle: Text(phone.isNotEmpty && phone != label ? phone : (status.isEmpty ? 'unknown' : status),
            style: const TextStyle(color: AppColors.textLight, fontSize: 12.5)),
        trailing: StatusPill(connected ? 'connected' : (status.isEmpty ? 'unknown' : status)),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => WaSessionChatsPage(session: session))),
      ),
    );
  }
}
