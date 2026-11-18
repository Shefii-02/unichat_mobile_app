import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:unichat_mobile_app/core/network/api.dart';
import 'package:unichat_mobile_app/features/modules/_shared.dart';
import 'package:unichat_mobile_app/features/team_chat/team_api.dart';
import 'package:unichat_mobile_app/features/team_chat/team_chat_data.dart';
import 'package:unichat_mobile_app/features/team_chat/team_chat_style.dart';
import 'package:unichat_mobile_app/features/team_chat/team_chats_page.dart';

/// Pick one teammate → open (or create) the direct chat.
class NewChatPage extends ConsumerStatefulWidget {
  const NewChatPage({super.key});
  @override
  ConsumerState<NewChatPage> createState() => _NewChatPageState();
}

class _NewChatPageState extends ConsumerState<NewChatPage> {
  String _q = '';
  bool _busy = false;

  Future<void> _open(Map u) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final r = await TeamApi.post('/team-chat/chats', data: {'type': 'direct', 'user_id': u['id']});
      ref.read(teamChatsProvider.notifier).refresh();
      if (mounted) context.pushReplacement('/team-chat/${r['id']}');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final users = ref.watch(teamUsersProvider);
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: const GlassAppBar(title: Text('New chat', style: TextStyle(fontWeight: FontWeight.w800))),
      body: GlassBackground(
        child: SafeArea(
          child: Column(children: [
            const SizedBox(height: kToolbarHeight),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
              child: GlassCard(
                padding: EdgeInsets.zero,
                radius: 16,
                child: ListTile(
                  leading: const CircleAvatar(backgroundColor: Glass.accent, child: Icon(Icons.group_add_rounded, color: Colors.white)),
                  title: Text('New group', style: TextStyle(fontWeight: FontWeight.w800, color: Glass.text(context))),
                  trailing: Icon(Icons.chevron_right_rounded, color: Glass.muted(context)),
                  onTap: () => context.pushReplacement('/team-chat/new-group'),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: GlassCard(
                padding: EdgeInsets.zero,
                radius: 16,
                child: TextField(
                  onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
                  decoration: InputDecoration(
                    hintText: 'Search team members',
                    hintStyle: TextStyle(color: Glass.muted(context)),
                    prefixIcon: const Icon(Icons.search_rounded, color: Glass.accentDeep),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ),
            Expanded(
              child: users.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text(apiErrorMessage(e))),
                data: (list) {
                  final f = list.where((u) => _q.isEmpty || '${u['name']}'.toLowerCase().contains(_q)).toList();
                  return ListView.builder(
                    physics: teamScrollPhysics,
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 24),
                    itemCount: f.length,
                    itemBuilder: (_, i) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: GlassCard(
                        padding: EdgeInsets.zero,
                        radius: 18,
                        child: ListTile(
                          leading: ChatAvatar(name: '${f[i]['name']}', url: f[i]['avatar'] as String?),
                          title: Text('${f[i]['name']}', style: TextStyle(fontWeight: FontWeight.w700, color: Glass.text(context))),
                          subtitle: f[i]['department'] == null ? null : Text('${f[i]['department']}', style: TextStyle(color: Glass.muted(context))),
                          onTap: () => _open(f[i]),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Multi-select members + group name → create group. Also used to add members to an existing
/// group when [chatId] is given ([excludeIds] hides people already in it).
class NewGroupPage extends ConsumerStatefulWidget {
  const NewGroupPage({super.key, this.chatId, this.excludeIds = const {}});
  final int? chatId;
  final Set<int> excludeIds;
  @override
  ConsumerState<NewGroupPage> createState() => _NewGroupPageState();
}

class _NewGroupPageState extends ConsumerState<NewGroupPage> {
  final _name = TextEditingController();
  final _sel = <int>{};
  String _q = '';
  bool _busy = false;

  bool get _adding => widget.chatId != null;

  Future<void> _submit() async {
    if (_sel.isEmpty || (!_adding && _name.text.trim().isEmpty)) return;
    setState(() => _busy = true);
    try {
      if (_adding) {
        await Api.post('/team-chat/chats/${widget.chatId}/members', data: {'user_ids': _sel.toList()});
        ref.read(teamChatsProvider.notifier).refresh();
        if (mounted) context.pop(true);
      } else {
        final r = await TeamApi.post('/team-chat/chats', data: {'type': 'group', 'name': _name.text.trim(), 'member_ids': _sel.toList()});
        ref.read(teamChatsProvider.notifier).refresh();
        if (mounted) context.pushReplacement('/team-chat/${r['id']}');
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final users = ref.watch(teamUsersProvider);
    final all = users.value ?? const <Map<String, dynamic>>[];
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: GlassAppBar(title: Text(_adding ? 'Add members' : 'New group', style: const TextStyle(fontWeight: FontWeight.w800))),
      floatingActionButton: _sel.isEmpty
          ? null
          : FloatingActionButton.extended(
              backgroundColor: Glass.accent,
              foregroundColor: Colors.white,
              onPressed: _busy ? null : _submit,
              icon: _busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.check_rounded),
              label: Text(_adding ? 'Add ${_sel.length}' : 'Create (${_sel.length})'),
            ),
      body: GlassBackground(
        child: SafeArea(
          child: Column(children: [
            const SizedBox(height: kToolbarHeight),
            if (!_adding)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: GlassCard(
                  padding: EdgeInsets.zero,
                  radius: 16,
                  child: TextField(
                    controller: _name,
                    maxLength: 80,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: 'Group name',
                      hintStyle: TextStyle(color: Glass.muted(context)),
                      prefixIcon: const Icon(Icons.groups_rounded, color: Glass.accentDeep),
                      counterText: '',
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ),
            // selected members as removable chips
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              child: _sel.isEmpty
                  ? const SizedBox(width: double.infinity)
                  : SizedBox(
                      height: 82,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        physics: teamScrollPhysics,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        children: [
                          for (final u in all.where((u) => _sel.contains((u['id'] as num).toInt())))
                            Padding(
                              padding: const EdgeInsets.only(right: 12),
                              child: GestureDetector(
                                onTap: () => setState(() => _sel.remove((u['id'] as num).toInt())),
                                child: SizedBox(
                                  width: 56,
                                  child: Column(children: [
                                    Stack(clipBehavior: Clip.none, children: [
                                      ChatAvatar(name: '${u['name']}', url: u['avatar'] as String?, radius: 22),
                                      Positioned(right: -4, top: -4, child: Container(padding: const EdgeInsets.all(2), decoration: const BoxDecoration(color: Colors.grey, shape: BoxShape.circle), child: const Icon(Icons.close_rounded, size: 12, color: Colors.white))),
                                    ]),
                                    const SizedBox(height: 4),
                                    Text('${u['name']}'.split(' ').first, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: Glass.text(context))),
                                  ]),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: GlassCard(
                padding: EdgeInsets.zero,
                radius: 16,
                child: TextField(
                  onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
                  decoration: InputDecoration(
                    hintText: 'Search members',
                    hintStyle: TextStyle(color: Glass.muted(context)),
                    prefixIcon: const Icon(Icons.search_rounded, color: Glass.accentDeep),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ),
            Expanded(
              child: users.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text(apiErrorMessage(e))),
                data: (list) {
                  final f = list
                      .where((u) => !widget.excludeIds.contains((u['id'] as num).toInt()))
                      .where((u) => _q.isEmpty || '${u['name']}'.toLowerCase().contains(_q))
                      .toList();
                  return ListView.builder(
                    physics: teamScrollPhysics,
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 100),
                    itemCount: f.length,
                    itemBuilder: (_, i) {
                      final id = (f[i]['id'] as num).toInt();
                      final on = _sel.contains(id);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: GlassCard(
                          padding: EdgeInsets.zero,
                          radius: 18,
                          opacity: on ? 0.8 : 0.5,
                          child: CheckboxListTile(
                            value: on,
                            activeColor: Glass.accent,
                            onChanged: (v) => setState(() => v == true ? _sel.add(id) : _sel.remove(id)),
                            secondary: ChatAvatar(name: '${f[i]['name']}', url: f[i]['avatar'] as String?),
                            title: Text('${f[i]['name']}', style: TextStyle(fontWeight: FontWeight.w700, color: Glass.text(context))),
                            subtitle: f[i]['department'] == null ? null : Text('${f[i]['department']}', style: TextStyle(color: Glass.muted(context))),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
