import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:unichat_mobile_app/core/constants/app_colors.dart';
import 'package:unichat_mobile_app/core/network/wa_chat_api_service.dart';
import 'package:unichat_mobile_app/core/permissions/permission_guard.dart';
import 'package:unichat_mobile_app/core/widgets/app_avatar.dart';
import 'package:unichat_mobile_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:unichat_mobile_app/features/chats/presentation/pages/wa_session_chat_room_page.dart';
import 'package:unichat_mobile_app/features/modules/_shared.dart';
import 'package:unichat_mobile_app/features/modules/module_providers.dart';
import 'package:unichat_mobile_app/features/modules/wa_chat_api.dart';

/// WA Chat's "Chats" — mirrors frontend/src/pages/wa-chat/pages/Chats.tsx exactly: pick a
/// connected WhatsApp session first (a chat only exists *within* one session's account), then
/// show that session's live chat list straight from the gateway (not the separate WA Cloud
/// conversation log Laravel keeps for the official-API inbox — that's a different feature).
class ChatsPage extends ConsumerStatefulWidget {
  const ChatsPage({super.key});
  @override
  ConsumerState<ChatsPage> createState() => _ChatsPageState();
}

enum _ChatTab { all, unread, individual, group }

class _ChatsPageState extends ConsumerState<ChatsPage> {
  final _searchCtrl = TextEditingController();
  String _search = '';
  Rec? _session;
  List<Rec> _chats = [];
  bool _loadingChats = false;
  String? _chatsError;
  // True once the current error looks recoverable by minting a fresh key (missing key, or the
  // gateway itself rejected the current one with 401) — shows "Reconnect WA Chat" instead of a
  // dead-end "Retry" for either case.
  bool _authError = false;
  bool _reconnecting = false;
  // Set once a reconnect actually succeeds — `authProvider`'s cached UserModel doesn't
  // refresh itself just because the company's wa_chat_token changed server-side, so this
  // overrides it locally rather than requiring a full re-login to pick the new key up.
  String? _apiKeyOverride;
  Map<String, String?> _pictures = {};

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  String? get _apiKey => _apiKeyOverride ?? ref.read(authProvider).value?.waContactToken;

  Future<void> _reconnectApiKey() async {
    setState(() => _reconnecting = true);
    try {
      final res = await WaChatApi.reconnectToken();
      final key = res['wa_chat_token'] as String?;
      if (key == null || key.isEmpty) {
        throw Exception('Gateway did not return a key.');
      }
      if (!mounted) return;
      setState(() { _apiKeyOverride = key; _reconnecting = false; });
      await _loadChats();
    } catch (e) {
      if (!mounted) return;
      setState(() => _reconnecting = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Couldn't reconnect — ${apiErrorMessage(e)}")));
    }
  }

  Future<void> _selectSession(Rec s) async {
    setState(() { _session = s; _loadingChats = true; _chatsError = null; _chats = []; });
    await _loadChats();
  }

  Future<void> _loadChats() async {
    final session = _session;
    final apiKey = _apiKey;
    if (session == null) return;
    if (apiKey == null || apiKey.isEmpty) {
      // Was previously a silent early-return here, which left `_loadingChats` stuck `true`
      // forever (set by _selectSession just before calling this) — the whole page just sat
      // on its loading spinner with no way to tell why, since nothing ever surfaced that the
      // company has no WA Chat gateway key provisioned yet.
      setState(() {
        _loadingChats = false;
        _authError = true;
        _chatsError = 'No WhatsApp Chat gateway key on this account yet.';
      });
      return;
    }
    final sessionName = str(session['session_name'], '');
    if (sessionName.isEmpty) {
      setState(() {
        _loadingChats = false;
        _chatsError = 'This session has no gateway id yet — it may still be provisioning. Try again shortly.';
      });
      return;
    }
    setState(() { _loadingChats = true; _chatsError = null; _authError = false; });
    try {
      final chats = await WaChatApiService.getChats(sessionName, apiKey);
      chats.sort((a, b) => (num.tryParse('${b['timestamp'] ?? 0}') ?? 0)
          .compareTo(num.tryParse('${a['timestamp'] ?? 0}') ?? 0));
      if (!mounted) return;
      setState(() { _chats = chats; _loadingChats = false; });
      _loadPictures(sessionName, apiKey, chats);
    } catch (e) {
      if (!mounted) return;
      // An expired/revoked token surfaces as a 401 from the gateway. Deliberately NOT
      // auto-reconnected: reconnecting mints a fresh gateway key AND REVOKES THE OLD ONE
      // (WaChatTokenService::provision), and this key is shared by every client on the
      // company's account — the web app, other devices, anyone else's open session. Firing
      // that automatically the moment any one client sees a transient 401 kicks every other
      // concurrently-open client off, including ones whose key was actually still fine. Show
      // the manual "Reconnect WA Chat" button instead and let a human decide.
      final unauthorized = e is DioException && e.response?.statusCode == 401;
      setState(() { _chatsError = apiErrorMessage(e); _loadingChats = false; _authError = unauthorized; });
    }
  }

  /// Best-effort, batched — a picture load failing (or the gateway not answering within budget)
  /// just leaves those tiles on their initials fallback, never blocks the chat list itself.
  Future<void> _loadPictures(String sessionName, String apiKey, List<Rec> chats) async {
    final ids = chats.map((c) => str(c['id'], '')).where((id) => id.isNotEmpty).toList();
    if (ids.isEmpty) return;
    try {
      final pictures = await WaChatApiService.getProfilePictures(sessionName, apiKey, ids);
      if (mounted) setState(() => _pictures = pictures);
    } catch (_) {}
  }

  String _tabLabel(_ChatTab t) => switch (t) {
        _ChatTab.all => 'All',
        _ChatTab.unread => 'Unread',
        _ChatTab.individual => 'Individual',
        _ChatTab.group => 'Group',
      };

  void _openChat(Rec chat) {
    final session = _session;
    final apiKey = _apiKey;
    if (session == null || apiKey == null) return;
    final sessionName = str(session['session_name'], '');
    final chatId = str(chat['id'], '');
    // Best-effort, matching the web's debounced mark-as-read on opening a chat.
    WaChatApiService.markChatRead(sessionName, apiKey, chatId).catchError((_) {});
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => WaSessionChatRoomPage(
        sessionName: sessionName,
        apiKey: apiKey,
        chatId: chatId,
        chatName: str(chat['name'], 'Unknown'),
        isGroup: chat['isGroup'] == true,
        allChats: _chats,
      ),
    )).then((_) => _loadChats());
  }

  _ChatTab _tab = _ChatTab.all;

  List<Rec> get _filteredChats {
    var list = _chats;
    switch (_tab) {
      case _ChatTab.all:
        break;
      case _ChatTab.unread:
        list = list.where((c) => (num.tryParse('${c['unreadCount'] ?? 0}') ?? 0) > 0).toList();
      case _ChatTab.individual:
        list = list.where((c) => c['isGroup'] != true).toList();
      case _ChatTab.group:
        list = list.where((c) => c['isGroup'] == true).toList();
    }
    if (_search.isEmpty) return list;
    final q = _search.toLowerCase();
    return list.where((c) {
      final name = str(c['name'], '').toLowerCase();
      final last = str(c['lastMessage'], '').toLowerCase();
      return name.contains(q) || last.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (!PermissionGuard.can('wa_chat.chats.view')) {
      return Scaffold(
        appBar: AppBar(title: const Text('WA Chats')),
        body: Center(
          child: Text("You don't have access to this section",
              style: TextStyle(color: context.mutedColor)),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        backgroundColor: AppColors.primaryDark,
        elevation: 0,
        title: const Text('Chats', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
      ),
      body: Column(
        children: [
          _SessionPicker(
            selected: _session,
            onSelected: _selectSession,
            onReady: (first) {
              if (_session == null && first != null) _selectSession(first);
            },
          ),
          if (_session != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: TextField(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _search = v.trim()),
                decoration: InputDecoration(
                  hintText: 'Search chats…',
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  filled: true,
                  fillColor: Colors.white,
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
              child: Row(
                children: [
                  for (final t in _ChatTab.values) ...[
                    ChoiceChip(
                      label: Text(_tabLabel(t)),
                      selected: _tab == t,
                      onSelected: (_) => setState(() => _tab = t),
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
            Expanded(child: _chatsBody()),
          ] else
            const Expanded(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Text('Connect and start a WhatsApp session under Sessions to use Chats.',
                      textAlign: TextAlign.center, style: TextStyle(color: AppColors.textLight)),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _chatsBody() {
    if (_loadingChats) return const Center(child: CircularProgressIndicator());
    if (_chatsError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_authError ? _chatsError! : "Couldn't load chats — $_chatsError",
                  textAlign: TextAlign.center),
              const SizedBox(height: 12),
              if (_authError)
                FilledButton(
                  onPressed: _reconnecting ? null : _reconnectApiKey,
                  child: _reconnecting
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Reconnect WA Chat'),
                )
              else
                OutlinedButton(onPressed: _loadChats, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    final chats = _filteredChats;
    if (chats.isEmpty) {
      return const Center(child: Text('No chats yet', style: TextStyle(color: AppColors.textLight)));
    }
    return RefreshIndicator(
      onRefresh: _loadChats,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: chats.length,
        itemBuilder: (_, i) => _ChatTile(
          chat: chats[i],
          pictureUrl: _pictures[str(chats[i]['id'], '')],
          onTap: () => _openChat(chats[i]),
        ),
      ),
    );
  }
}

/// A dropdown of this company's own WA Chat sessions (Laravel `/waha/sessions`) — the
/// `session_name` field is the gateway id every subsequent call is scoped to.
class _SessionPicker extends ConsumerWidget {
  const _SessionPicker({required this.selected, required this.onSelected, required this.onReady});
  final Rec? selected;
  final ValueChanged<Rec> onSelected;
  final ValueChanged<Rec?> onReady;

  static const _connectedStatuses = {'ready', 'connected', 'working', 'authenticated'};

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(wahaSessionsProvider);
    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(16),
        child: LinearProgressIndicator(),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(16),
        child: Text("Couldn't load sessions — ${apiErrorMessage(e)}",
            style: const TextStyle(color: AppColors.error, fontSize: 12)),
      ),
      data: (sessions) {
        final ready = sessions.where((s) => _connectedStatuses.contains(str(s['status'], '').toLowerCase())).toList();
        final options = ready.isNotEmpty ? ready : sessions;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (selected == null) onReady(options.isNotEmpty ? options.first : null);
        });
        if (options.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Text('No WhatsApp sessions yet — add one under Sessions.',
                style: TextStyle(color: AppColors.textLight, fontSize: 12.5)),
          );
        }
        final sel = selected != null && options.any((s) => s['id'] == selected!['id']) ? selected : options.first;
        return Container(
          color: AppColors.primaryDark,
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: sel?['id'] as int?,
              isExpanded: true,
              dropdownColor: AppColors.primaryDark,
              icon: const Icon(Icons.expand_more_rounded, color: Colors.white70),
              style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
              items: options.map((s) {
                final label = str(s['display_name'] ?? s['phone'] ?? s['session_name'], 'Session');
                final phone = str(s['phone'], '');
                return DropdownMenuItem(
                  value: s['id'] as int?,
                  child: Text(phone.isNotEmpty && phone != label ? '$label · $phone' : label,
                      overflow: TextOverflow.ellipsis),
                );
              }).toList(),
              onChanged: (id) {
                final s = options.firstWhere((s) => s['id'] == id, orElse: () => options.first);
                onSelected(s);
              },
            ),
          ),
        );
      },
    );
  }
}

class _ChatTile extends StatelessWidget {
  final Rec chat;
  final String? pictureUrl;
  final VoidCallback onTap;
  const _ChatTile({required this.chat, required this.onTap, this.pictureUrl});

  @override
  Widget build(BuildContext context) {
    final name = str(chat['name'], 'Unknown');
    final lastMsg = str(chat['lastMessage'], '');
    final unread = (num.tryParse('${chat['unreadCount'] ?? 0}') ?? 0).toInt();
    final isGroup = chat['isGroup'] == true;
    final ts = chat['timestamp'] != null
        ? DateTime.fromMillisecondsSinceEpoch((num.tryParse('${chat['timestamp']}') ?? 0).toInt() * 1000)
        : null;

    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade100))),
          child: Row(
            children: [
              Stack(
                children: [
                  AppAvatar(name: name, imageUrl: pictureUrl, size: 48),
                  if (isGroup)
                    Positioned(
                      right: 0, bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                        child: const Icon(Icons.groups_rounded, size: 14, color: AppColors.textSecondary),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(lastMsg.isEmpty ? 'No messages yet' : lastMsg,
                        style: TextStyle(color: unread > 0 ? AppColors.textPrimary : AppColors.textLight, fontSize: 13, fontWeight: unread > 0 ? FontWeight.w600 : FontWeight.w400),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (ts != null)
                    Text(when(ts.toIso8601String()), style: const TextStyle(color: AppColors.textLight, fontSize: 11)),
                  const SizedBox(height: 6),
                  if (unread > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(10)),
                      child: Text('$unread', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
