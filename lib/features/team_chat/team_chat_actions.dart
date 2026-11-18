import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:unichat_mobile_app/core/network/api.dart';
import 'package:unichat_mobile_app/features/team_chat/team_chat_data.dart';

/// "Mute for 8 hours / 1 week / always" sheet (WhatsApp style) — works for direct chats and groups.
/// If the chat is already muted this just unmutes it. Returns true when something changed.
Future<bool> toggleMuteChat(BuildContext context, WidgetRef ref, {required int chatId, required bool muted}) async {
  String? duration;
  if (muted) {
    duration = 'unmute';
  } else {
    duration = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: Align(alignment: Alignment.centerLeft, child: Text('Mute notifications', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Align(alignment: Alignment.centerLeft, child: Text('You will still get @mentions.', style: TextStyle(fontSize: 12.5))),
          ),
          for (final o in const [('8h', '8 hours'), ('1w', '1 week'), ('always', 'Always')])
            ListTile(leading: const Icon(Icons.volume_off_rounded), title: Text(o.$2), onTap: () => Navigator.pop(context, o.$1)),
        ]),
      ),
    );
  }
  if (duration == null) return false;
  try {
    await Api.post('/team-chat/chats/$chatId/mute', data: duration == 'unmute' ? {'muted': false} : {'muted': true, 'duration': duration});
    ref.read(teamChatsProvider.notifier).refresh();
    if (context.mounted) {
      ScaffoldMessenger.of(context)..hideCurrentSnackBar()..showSnackBar(SnackBar(content: Text(duration == 'unmute' ? 'Notifications on' : 'Chat muted')));
    }
    return true;
  } catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
    return false;
  }
}

/// Report a message to the company's admins.
Future<void> reportTeamMessage(BuildContext context, int messageId) async {
  String reason = 'inappropriate';
  final note = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: const Text('Report message'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Company admins will review it. The sender is not told who reported.', style: TextStyle(fontSize: 12.5)),
            const SizedBox(height: 8),
            for (final r in const [
              ('inappropriate', 'Inappropriate content'),
              ('harassment', 'Harassment or bullying'),
              ('spam', 'Spam'),
              ('other', 'Something else'),
            ])
              RadioListTile<String>(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: r.$1,
                groupValue: reason,
                title: Text(r.$2),
                onChanged: (v) => set(() => reason = v ?? reason),
              ),
            TextField(controller: note, maxLength: 500, maxLines: 2, decoration: const InputDecoration(labelText: 'Add a note (optional)')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Report')),
        ],
      ),
    ),
  );
  if (ok != true) return;
  try {
    await Api.post('/team-chat/messages/$messageId/report', data: {'reason': reason, if (note.text.trim().isNotEmpty) 'note': note.text.trim()});
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reported to company admins')));
  } catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
  }
}
