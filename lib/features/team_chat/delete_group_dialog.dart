import 'package:flutter/material.dart';
import 'package:unichat_mobile_app/core/network/api.dart';
import 'package:unichat_mobile_app/core/permissions/permission_guard.dart';

/// Only people whose role holds `team_chat.delete` may delete a conversation (1:1 or group) — nothing else grants it.
bool get canDeleteChats => PermissionGuard.teamChatEnabled && PermissionGuard.can('team_chat.delete');

/// Asks what to do with a conversation's shared photos, videos, voice notes and files when it is deleted.
/// Returns `true` = delete the chat, its messages AND all its media (frees storage), `false` = delete the messages but keep the
/// files in the Media Library, `null` = cancelled.
Future<bool?> askDeleteGroup(BuildContext context, String name, {bool group = true}) {
  return showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(group ? 'Delete group' : 'Delete chat'),
      content: Text('"$name" and all its messages will be deleted for everyone'
          '${group ? '' : ' — both of you lose this conversation'}.\n\nWhat about the photos, videos, voice notes and files shared in it?'),
      actionsOverflowDirection: VerticalDirection.down,
      actionsOverflowButtonSpacing: 4,
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Delete chat, keep media')),
        TextButton(
          onPressed: () => Navigator.pop(c, true),
          child: const Text('Delete chat and media', style: TextStyle(color: Colors.red)),
        ),
      ],
    ),
  );
}

/// What a delete / clear action did.
enum ChatForget { none, cleared, hidden, deleted }

enum _Scope { clear, me, everyone }

/// "Delete or clear" for one conversation — personal options for everyone, "for everyone" only with `team_chat.delete`:
///  · Clear chat       my history disappears, the conversation stays in my list (only me)
///  · Delete for me    also leaves my list; returns by itself when someone writes again (only me)
///  · Delete for everyone  gone for every member; asks what to do with the shared media
Future<ChatForget> deleteChatFlow(BuildContext context, {required int chatId, required String name, required bool group, bool onlyPersonal = false}) async {
  final everyoneAllowed = canDeleteChats && !onlyPersonal;
  final scope = await showDialog<_Scope>(
    context: context,
    builder: (c) => SimpleDialog(
      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
      children: [
        _opt(c, Icons.cleaning_services_rounded, 'Clear chat', 'Removes the messages for you only. The conversation stays in your list.', _Scope.clear),
        _opt(c, Icons.visibility_off_rounded, 'Delete for me',
            'Removes it from your list.${group ? ' You stay in the group.' : ''} It comes back if someone writes again. Nobody else is affected.', _Scope.me),
        if (everyoneAllowed)
          _opt(c, Icons.delete_forever_rounded, 'Delete for everyone',
              'Deletes it and all its messages for ${group ? 'every member' : 'both of you'}. Cannot be undone.', _Scope.everyone, color: Colors.red),
      ],
    ),
  );
  if (scope == null || !context.mounted) return ChatForget.none;
  try {
    switch (scope) {
      case _Scope.clear:
        await Api.post('/team-chat/chats/$chatId/clear');
        return ChatForget.cleared;
      case _Scope.me:
        await Api.post('/team-chat/chats/$chatId/hide');
        return ChatForget.hidden;
      case _Scope.everyone:
        final withMedia = await askDeleteGroup(context, name, group: group);
        if (withMedia == null || !context.mounted) return ChatForget.none;
        await Api.delete('/team-chat/chats/$chatId?delete_media=${withMedia ? 1 : 0}');
        return ChatForget.deleted;
    }
  } catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
    return ChatForget.none;
  }
}

Widget _opt(BuildContext c, IconData icon, String title, String hint, _Scope v, {Color? color}) => SimpleDialogOption(
      onPressed: () => Navigator.pop(c, v),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(fontWeight: FontWeight.w700, color: color)),
            const SizedBox(height: 2),
            Text(hint, style: const TextStyle(fontSize: 12, color: Colors.black54)),
          ]),
        ),
      ]),
    );
