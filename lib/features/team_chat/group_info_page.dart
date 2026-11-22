import 'package:dio/dio.dart';
import 'package:unichat_mobile_app/features/team_chat/delete_group_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:unichat_mobile_app/core/network/api.dart';
import 'package:unichat_mobile_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:unichat_mobile_app/features/team_chat/chat_media_page.dart';
import 'package:unichat_mobile_app/features/team_chat/message_info_page.dart';
import 'package:unichat_mobile_app/features/team_chat/team_api.dart';
import 'package:unichat_mobile_app/features/team_chat/team_chat_actions.dart';
import 'package:unichat_mobile_app/features/team_chat/team_chat_data.dart';
import 'package:unichat_mobile_app/features/team_chat/team_chat_pickers.dart';
import 'package:unichat_mobile_app/features/team_chat/team_chat_style.dart';
import 'package:unichat_mobile_app/features/team_chat/team_chats_page.dart';

/// Chat info (glass UI). Group: photo + name, shared media / starred, mute (8 h / 1 week / always),
/// permissions (who can send, edit info, add members), members with admin tools, people who left, leave /
/// delete. Direct chat: the person, shared media, starred and mute.
class GroupInfoPage extends ConsumerStatefulWidget {
  const GroupInfoPage({super.key, required this.chatId});
  final int chatId;
  @override
  ConsumerState<GroupInfoPage> createState() => _GroupInfoPageState();
}

class _GroupInfoPageState extends ConsumerState<GroupInfoPage> {
  Map<String, dynamic>? _info;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await TeamApi.one('/team-chat/chats/${widget.chatId}');
      if (mounted) setState(() { _info = d; _error = null; });
    } catch (e) {
      if (mounted) setState(() => _error = apiErrorMessage(e));
    }
  }

  Future<void> _do(Future<dynamic> Function() fn, {bool popAfter = false}) async {
    try {
      await fn();
      ref.read(teamChatsProvider.notifier).refresh();
      if (popAfter) {
        if (mounted) context.go('/team-chat');
        return;
      }
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
    }
  }

  Future<void> _rename(String current) async {
    final c = TextEditingController(text: current);
    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Rename group'),
        content: TextField(controller: c, autofocus: true, maxLength: 80),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, c.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) _do(() => Api.patch('/team-chat/chats/${widget.chatId}', data: {'name': name}));
  }

  Future<void> _changePhoto() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85, maxWidth: 800);
    if (x == null) return;
    _do(() async => Api.post('/team-chat/chats/${widget.chatId}/avatar', data: FormData.fromMap({'file': await MultipartFile.fromFile(x.path, filename: x.name)})));
  }

  Future<bool> _confirm(String title, String body, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(action)),
          ],
        ),
      ) ??
      false;

  Widget _section(String title, List<Widget> children) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.fromLTRB(6, 0, 6, 6), child: Text(title, style: TextStyle(color: Glass.muted(context), fontWeight: FontWeight.w800, fontSize: 12, letterSpacing: 0.8))),
          GlassCard(padding: const EdgeInsets.symmetric(vertical: 4), child: Column(children: children)),
        ]),
      );

  Widget _switch(IconData icon, String title, String sub, bool value, ValueChanged<bool> onChanged) => SwitchListTile(
        secondary: Icon(icon, color: Glass.accentDeep),
        title: Text(title, style: TextStyle(fontWeight: FontWeight.w700, color: Glass.text(context))),
        subtitle: Text(sub, style: TextStyle(color: Glass.muted(context), fontSize: 12)),
        value: value,
        activeColor: Glass.accent,
        onChanged: onChanged,
      );

  Widget _link(IconData icon, String title, VoidCallback onTap, {String? sub, Color? color}) => ListTile(
        leading: Icon(icon, color: color ?? Glass.accentDeep),
        title: Text(title, style: TextStyle(fontWeight: FontWeight.w700, color: color ?? Glass.text(context))),
        subtitle: sub == null ? null : Text(sub, style: TextStyle(color: Glass.muted(context), fontSize: 12)),
        trailing: color == null ? Icon(Icons.chevron_right_rounded, color: Glass.muted(context)) : null,
        onTap: onTap,
      );

  @override
  Widget build(BuildContext context) {
    final i = _info;
    final me = ref.watch(authProvider).value?.id;
    if (i == null) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        appBar: const GlassAppBar(),
        body: GlassBackground(child: Center(child: _error != null ? Text(_error!) : const CircularProgressIndicator())),
      );
    }
    final group = i['type'] == 'group';
    final admin = i['my_role'] == 'admin';
    final members = (i['members'] as List).whereType<Map>().toList();
    final former = (i['former_members'] as List? ?? const []).whereType<Map>().toList();
    final other = members.firstWhere((m) => m['id'] != me, orElse: () => {'name': ''});
    final title = group ? '${i['name']}' : '${other['name']}';
    final canEditInfo = admin || i['only_admins_edit'] != true;
    final canAdd = admin || i['only_admins_add'] != true;
    final muted = i['muted'] == true;
    final mutedUntil = i['muted_until'] != null ? DateTime.tryParse('${i['muted_until']}')?.toLocal() : null;

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: GlassAppBar(title: Text(group ? 'Group info' : 'Contact info', style: const TextStyle(fontWeight: FontWeight.w800))),
      body: GlassBackground(
        child: SafeArea(
          child: ListView(
            physics: teamScrollPhysics,
            padding: const EdgeInsets.fromLTRB(14, kToolbarHeight + 8, 14, 34),
            children: [
              // header
              Column(children: [
                GestureDetector(
                  onTap: group && canEditInfo ? _changePhoto : null,
                  child: Stack(children: [
                    ChatAvatar(name: title, group: group, radius: 52, url: group ? i['avatar'] as String? : (other['avatar'] as String?)),
                    if (group && canEditInfo)
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.all(7),
                          decoration: const BoxDecoration(color: Glass.accent, shape: BoxShape.circle),
                          child: const Icon(Icons.camera_alt_rounded, size: 16, color: Colors.white),
                        ),
                      ),
                  ]),
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: group && canEditInfo ? () => _rename(title) : null,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Flexible(child: Text(title, textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Glass.text(context)))),
                    if (group && canEditInfo) Padding(padding: const EdgeInsets.only(left: 6), child: Icon(Icons.edit_rounded, size: 17, color: Glass.muted(context))),
                  ]),
                ),
                if (group) Text('Group · ${members.length} members', style: TextStyle(color: Glass.muted(context))),
              ]),
              const SizedBox(height: 18),
              _section('SHARED', [
                _link(Icons.perm_media_rounded, 'Media, links and docs', () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatMediaPage(chatId: widget.chatId, title: title)))),
                _link(Icons.star_rounded, 'Starred messages', () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => StarredMessagesPage(chatId: widget.chatId))), color: null),
              ]),
              _section('NOTIFICATIONS', [
                ListTile(
                  leading: Icon(muted ? Icons.volume_off_rounded : Icons.notifications_active_rounded, color: Glass.accentDeep),
                  title: Text(muted ? 'Muted' : 'Mute notifications', style: TextStyle(fontWeight: FontWeight.w700, color: Glass.text(context))),
                  subtitle: Text(
                    muted ? (mutedUntil != null ? 'Until ${teamDay(mutedUntil.toIso8601String())}, ${teamTime(mutedUntil.toIso8601String())} · tap to unmute' : 'Until you turn it on · tap to unmute') : '8 hours, 1 week or always — @mentions still notify you',
                    style: TextStyle(color: Glass.muted(context), fontSize: 12),
                  ),
                  onTap: () async { if (await toggleMuteChat(context, ref, chatId: widget.chatId, muted: muted)) _load(); },
                ),
              ]),
              if (group && admin)
                _section('GROUP PERMISSIONS', [
                  _switch(Icons.send_rounded, 'Members can send messages', 'Turn off to let only admins post', i['only_admins_post'] != true,
                      (v) => _do(() => Api.patch('/team-chat/chats/${widget.chatId}', data: {'only_admins_post': !v}))),
                  _switch(Icons.edit_note_rounded, 'Members can edit group info', 'Name, photo and pinning messages', i['only_admins_edit'] != true,
                      (v) => _do(() => Api.patch('/team-chat/chats/${widget.chatId}', data: {'only_admins_edit': !v}))),
                  _switch(Icons.person_add_alt_1_rounded, 'Members can add members', 'Turn off to let only admins add people', i['only_admins_add'] != true,
                      (v) => _do(() => Api.patch('/team-chat/chats/${widget.chatId}', data: {'only_admins_add': !v}))),
                ]),
              if (group)
                _section('MEMBERS · ${members.length}', [
                  if (canAdd)
                    ListTile(
                      leading: const CircleAvatar(backgroundColor: Glass.accent, child: Icon(Icons.person_add_alt_1_rounded, color: Colors.white)),
                      title: Text('Add members', style: TextStyle(fontWeight: FontWeight.w800, color: Glass.text(context))),
                      onTap: () async {
                        final added = await Navigator.of(context).push<bool>(MaterialPageRoute(
                          builder: (_) => NewGroupPage(chatId: widget.chatId, excludeIds: {for (final m in members) (m['id'] as num).toInt()}),
                        ));
                        if (added == true) _load();
                      },
                    ),
                  for (final m in members)
                    ListTile(
                      leading: ChatAvatar(name: '${m['name']}', url: m['avatar'] as String?),
                      title: Text(m['id'] == me ? 'You' : '${m['name']}', style: TextStyle(fontWeight: FontWeight.w700, color: Glass.text(context))),
                      trailing: m['role'] == 'admin'
                          ? Container(
                              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                              decoration: BoxDecoration(color: Glass.accent.withOpacity(0.14), borderRadius: BorderRadius.circular(99)),
                              child: const Text('Admin', style: TextStyle(color: Glass.accentDeep, fontSize: 11, fontWeight: FontWeight.w800)),
                            )
                          : null,
                      onTap: m['id'] == me ? null : () => _memberSheet(m, admin),
                    ),
                ]),
              if (group && former.isNotEmpty && admin)
                _section('LEFT / REMOVED · ${former.length}', [
                  for (final m in former)
                    ListTile(
                      dense: true,
                      leading: ChatAvatar(name: '${m['name']}', url: m['avatar'] as String?, radius: 17),
                      title: Text('${m['name']}', style: TextStyle(color: Glass.muted(context))),
                      subtitle: Text('Left ${teamDay(m['left_at'])}', style: TextStyle(color: Glass.muted(context), fontSize: 11.5)),
                    ),
                ]),
              if (group)
                _section('', [
                  _link(Icons.exit_to_app_rounded, 'Leave group', () async {
                    if (await _confirm('Leave group', 'You will stop receiving messages from this group.', 'Leave')) {
                      _do(() => Api.delete('/team-chat/chats/${widget.chatId}/members/$me'), popAfter: true);
                    }
                  }, color: Colors.red),
                  _link(Icons.delete_forever_rounded, 'Delete / clear chat…', () async {
                    final res = await deleteChatFlow(context, chatId: widget.chatId, name: '${i['name'] ?? 'this group'}', group: true);
                    if (res != ChatForget.none && mounted) Navigator.of(context).pop(true);
                  }, color: Colors.red),
                ]),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _memberSheet(Map m, bool admin) async {
    final c = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(12),
        child: GlassCard(
          opacity: 0.9,
          radius: 24,
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: SafeArea(
            top: false,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              ListTile(leading: ChatAvatar(name: '${m['name']}', url: m['avatar'] as String?, radius: 18), title: Text('${m['name']}', style: const TextStyle(fontWeight: FontWeight.w800))),
              ListTile(leading: const Icon(Icons.chat_bubble_outline_rounded), title: Text('Message ${m['name']}'), onTap: () => Navigator.pop(ctx, 'dm')),
              if (admin) ...[
                ListTile(leading: const Icon(Icons.admin_panel_settings_rounded), title: Text(m['role'] == 'admin' ? 'Remove as admin' : 'Make group admin'), onTap: () => Navigator.pop(ctx, 'role')),
                ListTile(leading: const Icon(Icons.person_remove_rounded, color: Colors.red), title: Text('Remove ${m['name']}', style: const TextStyle(color: Colors.red)), onTap: () => Navigator.pop(ctx, 'remove')),
              ],
            ]),
          ),
        ),
      ),
    );
    if (c == null) return;
    if (c == 'dm') {
      try {
        final r = await TeamApi.post('/team-chat/chats', data: {'type': 'direct', 'user_id': m['id']});
        if (mounted) context.push('/team-chat/${r['id']}');
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
      }
    } else if (c == 'role') {
      _do(() => Api.post('/team-chat/chats/${widget.chatId}/members/${m['id']}/role', data: {'role': m['role'] == 'admin' ? 'member' : 'admin'}));
    } else if (c == 'remove' && await _confirm('Remove member', 'Remove ${m['name']} from this group?', 'Remove')) {
      _do(() => Api.delete('/team-chat/chats/${widget.chatId}/members/${m['id']}'));
    }
  }
}
