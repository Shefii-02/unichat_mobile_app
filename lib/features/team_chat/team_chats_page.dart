import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:unichat_mobile_app/core/permissions/permission_guard.dart';
import 'package:unichat_mobile_app/core/socket/socket_service.dart';
import 'package:unichat_mobile_app/features/team_chat/team_chat_actions.dart';
import 'package:unichat_mobile_app/features/team_chat/delete_group_dialog.dart';
import 'package:unichat_mobile_app/features/team_chat/team_chat_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:unichat_mobile_app/core/network/api.dart';
import 'package:unichat_mobile_app/core/theme/app_theme.dart';
import 'package:unichat_mobile_app/features/team_chat/team_chat_data.dart';
import 'package:unichat_mobile_app/features/team_chat/team_api.dart';

/// Avatar for a person or group: photo if present, else coloured initial / group icon.
class ChatAvatar extends StatelessWidget {
  const ChatAvatar({super.key, required this.name, this.url, this.group = false, this.radius = 22});
  final String name;
  final String? url;
  final bool group;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final seed = name.codeUnits.fold<int>(0, (a, b) => a + b);
    final color = Colors.primaries[seed % Colors.primaries.length].shade600;
    if (url != null && url!.isNotEmpty) {
      return CircleAvatar(radius: radius, backgroundImage: CachedNetworkImageProvider(url!));
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: color.withOpacity(0.18),
      child: group
          ? Icon(Icons.groups_rounded, color: color, size: radius)
          : Text(name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase(),
              style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: radius * 0.8)),
    );
  }
}

/// Bottom-nav "Chats" tab — light-blue glass UI. Tabs with live counts (the Unread / @Mentions tabs only
/// appear when there is something to show), New chat / New group quick actions, conversation search that
/// also finds messages, swipe actions (mute, mark read) and infinite-scroll paging.
class TeamChatsPage extends ConsumerStatefulWidget {
  const TeamChatsPage({super.key});
  @override
  ConsumerState<TeamChatsPage> createState() => _TeamChatsPageState();
}

class _TeamChatsPageState extends ConsumerState<TeamChatsPage> {
  final _scroll = ScrollController();
  final _search = TextEditingController();
  Timer? _debounce;
  bool _mentionsOnly = false;
  bool _searchOpen = false;
  List<Map<String, dynamic>> _msgHits = [];
  bool _msgSearching = false;
  int _searchGen = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 300) {
        ref.read(teamChatsProvider.notifier).loadMore();
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  void _onSearch(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      final q = v.trim();
      ref.read(teamChatsProvider.notifier).setQuery(q);
      final gen = ++_searchGen;
      if (q.length < 2) {
        if (mounted) setState(() { _msgHits = []; _msgSearching = false; });
        return;
      }
      setState(() => _msgSearching = true);
      try {
        final hits = await Api.list('/team-chat/search', query: {'q': q});
        if (mounted && gen == _searchGen) setState(() { _msgHits = hits; _msgSearching = false; });
      } catch (_) {
        if (mounted && gen == _searchGen) setState(() => _msgSearching = false);
      }
    });
  }

  void _closeSearch() {
    _search.clear();
    _onSearch('');
    setState(() => _searchOpen = false);
  }

  /// Shown when the plan does not include Team chat or the role may not use it.
  Widget _locked(BuildContext context) {
    final inPlan = PermissionGuard.entitled('team_chat');
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GlassBackground(
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.lock_outline_rounded, size: 48, color: Glass.muted(context)),
                const SizedBox(height: 12),
                Text('Team chat is not available', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Glass.text(context))),
                const SizedBox(height: 6),
                Text(
                  inPlan
                      ? 'Your role does not have permission to use team chat. Ask your admin to enable it.'
                      : 'Team chat is not part of your company\'s plan. Ask your admin to upgrade the plan or buy the add-on.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Glass.muted(context)),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!PermissionGuard.teamChatEnabled) return _locked(context);
    final st = ref.watch(teamChatsProvider);
    final unreadChats = st.count('unread_chats');
    final mentions = st.count('mentions');
    final chats = _mentionsOnly ? st.items.where((c) => ((c['unread_mentions'] as num?)?.toInt() ?? 0) > 0).toList() : st.items;
    final searching = st.query.length >= 2;
    // Unread / @ tabs disappear when their count is zero.
    if (st.type == 'unread' && unreadChats == 0 && !st.loading) {
      WidgetsBinding.instance.addPostFrameCallback((_) => ref.read(teamChatsProvider.notifier).setType('all'));
    }
    if (_mentionsOnly && mentions == 0) WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) setState(() => _mentionsOnly = false); });

    final tabs = <(String, String, int, bool)>[
      ('all', 'All', 0, false),
      ('direct', 'Chats', st.count('direct_unread'), false),
      ('group', 'Groups', st.count('group_unread'), false),
      if (unreadChats > 0) ('unread', 'Unread', unreadChats, true),
    ];

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GlassBackground(
        child: SafeArea(
          bottom: false,
          child: Column(children: [
            // ── header ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 12, 0),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Chats', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: Glass.text(context), letterSpacing: -0.5)),
                    Text(unreadChats > 0 ? '$unreadChats unread conversation${unreadChats > 1 ? 's' : ''}' : 'You\'re all caught up',
                        style: TextStyle(fontSize: 13, color: Glass.muted(context))),
                  ]),
                ),
                _roundBtn(context, Icons.search_rounded, () => setState(() => _searchOpen = !_searchOpen)),
                _roundBtn(context, Icons.star_rounded, () => context.push('/team-chat/starred')),
                if (PermissionGuard.teamChatModerate) _roundBtn(context, Icons.shield_outlined, () => context.push('/team-chat/admin')),
              ]),
            ),
            // ── search ──
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              child: _searchOpen
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                      child: GlassCard(
                        padding: EdgeInsets.zero,
                        radius: 16,
                        child: TextField(
                          controller: _search,
                          autofocus: true,
                          onChanged: _onSearch,
                          style: TextStyle(color: Glass.text(context)),
                          decoration: InputDecoration(
                            hintText: 'Search conversations and messages',
                            hintStyle: TextStyle(color: Glass.muted(context)),
                            prefixIcon: Icon(Icons.search_rounded, color: Glass.accentDeep),
                            suffixIcon: IconButton(icon: const Icon(Icons.close_rounded), onPressed: _closeSearch),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                    )
                  : const SizedBox(width: double.infinity),
            ),
            // ── new chat / new group ──
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
              child: Row(children: [
                // filled: true,
                Expanded(child: GlassPill(icon: Icons.chat_bubble_rounded, label: 'New chat', onTap: () => context.push('/team-chat/new'))),
                if (PermissionGuard.teamChatGroups) ...[
                  const SizedBox(width: 10),
                  Expanded(child: GlassPill(icon: Icons.group_add_rounded, label: 'New group', onTap: () => context.push('/team-chat/new-group'))),
                ],
              ]),
            ),
            // ── tabs with counts ──
            SizedBox(
              height: 52,
              child: ListView(
                scrollDirection: Axis.horizontal,
                physics: teamScrollPhysics,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                children: [
                  for (final t in tabs) _tab(context, t.$2, t.$3, selected: !_mentionsOnly && st.type == t.$1, hot: t.$4, onTap: () { setState(() => _mentionsOnly = false); ref.read(teamChatsProvider.notifier).setType(t.$1); }),
                  if (mentions > 0) _tab(context, '@ Mentions', mentions, selected: _mentionsOnly, hot: true, onTap: () => setState(() => _mentionsOnly = !_mentionsOnly)),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                color: Glass.accent,
                onRefresh: () => ref.read(teamChatsProvider.notifier).reload(),
                child: _list(context, st, chats, searching),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _roundBtn(BuildContext context, IconData icon, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(left: 6),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Ink(
            width: 42,
            height: 42,
            decoration: BoxDecoration(color: Glass.panel(context, a: 0.6), borderRadius: BorderRadius.circular(14), border: Border.all(color: Glass.border(context))),
            child: Icon(icon, size: 20, color: Glass.accentDeep),
          ),
        ),
      );

  Widget _tab(BuildContext context, String label, int count, {required bool selected, required bool hot, required VoidCallback onTap}) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: InkWell(
          borderRadius: BorderRadius.circular(99),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              gradient: selected ? const LinearGradient(colors: [Glass.accentSoft, Glass.accent]) : null,
              color: selected ? null : Glass.panel(context, a: 0.55),
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: selected ? Colors.transparent : Glass.border(context)),
              boxShadow: selected ? [BoxShadow(color: Glass.accent.withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 4))] : null,
            ),
            alignment: Alignment.center,
            child: Row(children: [
              Text(label, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: selected ? Colors.white : Glass.text(context))),
              if (count > 0) ...[
                const SizedBox(width: 7),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1.5),
                  decoration: BoxDecoration(color: selected ? Colors.white.withOpacity(0.28) : (hot ? const Color(0xFFEF4444) : Glass.accent), borderRadius: BorderRadius.circular(99)),
                  child: Text(count > 99 ? '99+' : '$count', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
                ),
              ],
            ]),
          ),
        ),
      );

  Widget _list(BuildContext context, TeamChatsState st, List<Map<String, dynamic>> chats, bool searching) {
    if (st.loading && st.items.isEmpty) return const Center(child: CircularProgressIndicator());
    if (st.error != null && st.items.isEmpty) {
      return ListView(physics: teamScrollPhysics, children: [
        const SizedBox(height: 80),
        Padding(padding: const EdgeInsets.all(24), child: Text(st.error!, textAlign: TextAlign.center, style: TextStyle(color: Glass.muted(context)))),
        Center(child: FilledButton(onPressed: () => ref.read(teamChatsProvider.notifier).reload(), child: const Text('Retry'))),
      ]);
    }
    final hasHits = searching && _msgHits.isNotEmpty;
    if (chats.isEmpty && !hasHits && !_msgSearching) {
      return ListView(controller: _scroll, physics: teamScrollPhysics, children: [
        const SizedBox(height: 70),
        Icon(_mentionsOnly ? Icons.alternate_email_rounded : Icons.forum_rounded, size: 64, color: Glass.accentSoft),
        const SizedBox(height: 12),
        Center(child: Text(_mentionsOnly ? 'No unread mentions' : (searching ? 'No chats found' : 'No conversations yet'), style: TextStyle(color: Glass.muted(context), fontSize: 15, fontWeight: FontWeight.w600))),
      ]);
    }
    return ListView(
      controller: _scroll,
      physics: teamScrollPhysics,
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 110),
      children: [
        for (final c in chats) _tile(context, c),
        if (st.loadingMore || (st.hasMore && !_mentionsOnly))
          const Padding(padding: EdgeInsets.all(16), child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))),
        if (searching) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 18, 6, 8),
            child: Text('MESSAGES', style: TextStyle(color: Glass.muted(context), fontWeight: FontWeight.w800, fontSize: 12, letterSpacing: 0.8)),
          ),
          if (_msgSearching) const Padding(padding: EdgeInsets.all(16), child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))),
          if (!_msgSearching && _msgHits.isEmpty) Padding(padding: const EdgeInsets.all(8), child: Text('No matching messages', style: TextStyle(color: Glass.muted(context)))),
          for (final h in _msgHits)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GlassCard(
                padding: EdgeInsets.zero,
                child: ListTile(
                  onTap: () => context.push('/team-chat/${h['chat_id']}?m=${h['id']}'),
                  leading: ChatAvatar(name: '${h['chat_name']}', group: h['chat_type'] == 'group'),
                  title: Text('${h['chat_name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w800, color: Glass.text(context))),
                  subtitle: Text('${h['sender_name'] ?? ''}: ${h['text'] ?? ''}', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: Glass.muted(context))),
                  trailing: Text(teamTime(h['created_at']), style: TextStyle(fontSize: 11, color: Glass.muted(context))),
                ),
              ),
            ),
        ],
      ],
    );
  }

  Future<void> _markRead(int id) async {
    final r = await SocketService().call('chat:read', {'chat_id': id});
    if (r == null) await Api.post('/team-chat/chats/$id/read');
    ref.read(teamChatsProvider.notifier).refresh();
  }

  Future<void> _openAtMention(BuildContext context, int chatId) async {
    int? msg;
    try {
      final mine = await TeamApi.list('/team-chat/mentions');
      final ids = [for (final x in mine) if ((x['chat_id'] as num?)?.toInt() == chatId && x['unread'] == true) (x['id'] as num).toInt()]..sort();
      if (ids.isNotEmpty) msg = ids.first;
    } catch (_) {}
    if (context.mounted) context.push('/team-chat/$chatId${msg != null ? '?m=$msg' : ''}');
  }

  Widget _tile(BuildContext context, Map c) {
    final id = (c['id'] as num).toInt();
    final unread = (c['unread'] as num?)?.toInt() ?? 0;
    final mentions = (c['unread_mentions'] as num?)?.toInt() ?? 0;
    final muted = c['muted'] == true;
    final group = c['type'] == 'group';
    final sender = group && c['last_message'] != null && c['last_sender'] != null ? '${c['last_sender']}: ' : '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Slidable(
        key: ValueKey('chat$id'),
        startActionPane: unread > 0
            ? ActionPane(motion: const BehindMotion(), extentRatio: 0.28, children: [
                SlidableAction(onPressed: (_) => _markRead(id), backgroundColor: Glass.accent, foregroundColor: Colors.white, icon: Icons.mark_chat_read_rounded, label: 'Read', borderRadius: BorderRadius.circular(18)),
              ])
            : null,
        endActionPane: ActionPane(motion: const BehindMotion(), extentRatio: 0.55, children: [
            SlidableAction(
              onPressed: (_) async {
                if (await deleteChatFlow(context, chatId: id, name: '${c['name'] ?? 'this chat'}', group: group) != ChatForget.none) ref.read(teamChatsProvider.notifier).refresh();
              },
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              icon: Icons.delete_rounded,
              label: 'Delete',
              borderRadius: BorderRadius.circular(18),
            ),
          SlidableAction(
            onPressed: (_) => toggleMuteChat(context, ref, chatId: id, muted: muted),
            backgroundColor: const Color(0xFF64748B),
            foregroundColor: Colors.white,
            icon: muted ? Icons.volume_up_rounded : Icons.volume_off_rounded,
            label: muted ? 'Unmute' : 'Mute',
            borderRadius: BorderRadius.circular(18),
          ),
        ]),
        child: GlassCard(
          padding: EdgeInsets.zero,
          opacity: unread > 0 ? 0.75 : 0.5,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => context.push('/team-chat/$id'),
            onLongPress: () => toggleMuteChat(context, ref, chatId: id, muted: muted),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(children: [
                ChatAvatar(name: '${c['name']}', url: c['avatar'] as String?, group: group, radius: 25),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text('${c['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15.5, fontWeight: unread > 0 ? FontWeight.w900 : FontWeight.w700, color: Glass.text(context)))),
                      if (muted) Padding(padding: const EdgeInsets.only(left: 4), child: Icon(Icons.volume_off_rounded, size: 14, color: Glass.muted(context))),
                      const SizedBox(width: 6),
                      Text(teamTime(c['last_message_at']), style: TextStyle(fontSize: 11.5, color: unread > 0 ? Glass.accent : Glass.muted(context), fontWeight: unread > 0 ? FontWeight.w800 : FontWeight.w500)),
                    ]),
                    const SizedBox(height: 3),
                    Row(children: [
                      Expanded(
                        child: Text(
                          c['last_message'] == null ? (group ? '${c['members_count']} members' : 'Say hi 👋') : '$sender${c['last_message']}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: unread > 0 ? Glass.text(context) : Glass.muted(context), fontWeight: unread > 0 ? FontWeight.w600 : FontWeight.w400, fontSize: 13.5),
                        ),
                      ),
                      if (unread > 0)
                        GestureDetector(
                          // "@ 5": tapping it opens the chat right at the first unread message that mentions me
                          onTap: mentions > 0 ? () => _openAtMention(context, id) : null,
                          child: Container(
                          margin: const EdgeInsets.only(left: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                          decoration: BoxDecoration(
                            // someone @mentioned you in here: one clear badge — "@ 5" = 5 unread, and some of them are for you
                            gradient: muted || mentions > 0 ? null : const LinearGradient(colors: [Glass.accentSoft, Glass.accent]),
                            color: mentions > 0 ? Glass.accentDeep : (muted ? Glass.muted(context) : null),
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text('${mentions > 0 ? '@ ' : ''}${unread > 99 ? '99+' : unread}', style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w800)),
                        )),
                    ]),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// "@ Mentions" quick access: every message that @mentions me, across all chats, newest first.
class MentionsPage extends ConsumerStatefulWidget {
  const MentionsPage({super.key});
  @override
  ConsumerState<MentionsPage> createState() => _MentionsPageState();
}

class _MentionsPageState extends ConsumerState<MentionsPage> {
  late Future<List<Map<String, dynamic>>> _f = Api.list('/team-chat/mentions');

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Mentions')),
        body: RefreshIndicator(
          onRefresh: () async { setState(() => _f = Api.list('/team-chat/mentions')); await _f; },
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _f,
            builder: (_, s) {
              if (s.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
              if (s.hasError) return ListView(children: [Padding(padding: const EdgeInsets.all(32), child: Text(apiErrorMessage(s.error!), textAlign: TextAlign.center))]);
              final rows = s.data ?? const [];
              if (rows.isEmpty) {
                return ListView(children: [
                  const SizedBox(height: 90),
                  Icon(Icons.alternate_email_rounded, size: 56, color: context.mutedColor),
                  const SizedBox(height: 12),
                  Center(child: Text('Nobody has mentioned you yet', style: TextStyle(color: context.mutedColor))),
                ]);
              }
              return ListView.separated(
                itemCount: rows.length,
                separatorBuilder: (_, __) => Divider(height: 1, indent: 72, color: context.lineColor),
                itemBuilder: (_, i) {
                  final m = rows[i];
                  final unread = m['unread'] == true;
                  return ListTile(
                    onTap: () => context.push('/team-chat/${m['chat_id']}?m=${m['id']}'),
                    leading: ChatAvatar(name: '${m['sender_name'] ?? m['chat_name']}'),
                    title: Text('${m['sender_name'] ?? ''} · ${m['chat_name']}', maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontWeight: unread ? FontWeight.w800 : FontWeight.w600)),
                    subtitle: Text('${m['body'] ?? ''}', maxLines: 2, overflow: TextOverflow.ellipsis),
                    trailing: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text(teamDay(m['created_at']), style: TextStyle(fontSize: 11, color: context.mutedColor)),
                      Text(teamTime(m['created_at']), style: TextStyle(fontSize: 11, color: context.mutedColor)),
                    ]),
                  );
                },
              );
            },
          ),
        ),
      );
}
