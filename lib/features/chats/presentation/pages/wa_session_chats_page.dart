import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:unichat_mobile_app/core/constants/app_colors.dart';
import 'package:unichat_mobile_app/core/network/wa_chat_api_service.dart';
import 'package:unichat_mobile_app/core/widgets/app_avatar.dart';
import 'package:unichat_mobile_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:unichat_mobile_app/features/chats/presentation/pages/wa_session_chat_room_page.dart';
import 'package:unichat_mobile_app/features/modules/_shared.dart';
import 'package:unichat_mobile_app/features/modules/wa_chat_api.dart';
import 'package:unichat_mobile_app/features/search/presentation/pages/global_search_page.dart';

/// One WhatsApp session's live chat list, straight from the gateway. Reached by tapping a
/// session on [ChatsPage] — the session-picker dropdown that used to live inline on that page
/// was replaced with this dedicated pushed page (session list -> tap -> just this session's
/// chats -> back -> pick another session), per the user's requested navigation shape.
class WaSessionChatsPage extends ConsumerStatefulWidget {
  const WaSessionChatsPage({super.key, required this.session});
  final Rec session;

  @override
  ConsumerState<WaSessionChatsPage> createState() => _WaSessionChatsPageState();
}

enum _ChatTab { all, unread, individual, group, mine, unassigned }

class _WaSessionChatsPageState extends ConsumerState<WaSessionChatsPage> {
  final _searchCtrl = TextEditingController();
  String _search = '';
  List<Rec> _chats = [];
  bool _loadingChats = true;
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
  // Reconnecting mints a fresh gateway key AND REVOKES THE OLD ONE, INSTANTLY (WaChatTokenService::
  // provision — no grace period, and it force-evicts the other key's live WebSocket too), and that
  // key is shared by every client on the company's account — the web app, other devices, anyone
  // else's open session. This used to auto-fire on a 401 as well as a missing key; that was reverted
  // after learning `WaChatShell.tsx` on the web side tried the exact same thing before and reverted
  // it (see its own comment), because it can silently revoke the token a concurrently-open web tab
  // is actively using, kicking it with no warning and no self-heal on that side. Now only the missing-
  // key case auto-fires (see _loadChats) — that one mints the FIRST key, so there is no existing
  // client to kick. A 401 (existing key rejected) always falls back to the manual "Reconnect WA Chat"
  // button, matching the web app's own deliberate behavior.
  bool _autoReconnectTried = false;
  Map<String, String?> _pictures = {};

  // `getChats` is a heavy gateway read (it serializes a whole chat list across the WhatsApp engine's
  // Chromium/CDP bridge) that can starve a DIFFERENT session's liveness probe long enough for the
  // gateway to disconnect it — refiring it on every pull-to-refresh made this app the bigger trigger
  // of that. Cached per session for 60s, mirroring frontend/src/pages/wa-chat/pages/Chats.tsx's own
  // `staleTime: 60_000`. Static so it survives navigating back to the session list and returning —
  // this page is pushed/popped fresh each visit, unlike the old single-page dropdown version. An
  // explicit pull-to-refresh still always hits the network — see the `force` param on _loadChats.
  static const _chatsStaleTtl = Duration(seconds: 60);
  static final Map<String, (List<Rec>, DateTime)> _chatsCache = {};

  // "Mine" / "Unassigned" tabs cross-reference the chat list against CRM leads (by phone,
  // last-10-digit match — same normalisation contact_info_page.dart's own phone search uses).
  // Lazily fetched the first time either tab is opened, since it costs extra round-trips the
  // other tabs don't need.
  bool _mineLoading = false;
  bool _mineFetched = false;
  Set<String> _minePhones = {};
  bool _unassignedLoading = false;
  bool _unassignedFetched = false;
  Set<String> _unassignedPhones = {};

  // An @lid chat's id is an opaque privacy id, not phone-derived — same problem
  // contact_info_page.dart's `_phoneDigits` solves for a single chat, resolved here for every
  // @lid chat in the list so the Mine/Unassigned tabs can match them by their real phone too.
  final Map<String, String> _resolvedLidPhones = {};

  String get _sessionName => str(widget.session['session_name'], '');

  String _last10(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    return digits.length <= 10 ? digits : digits.substring(digits.length - 10);
  }

  Future<void> _resolveLidPhonesForCurrentChats() async {
    final apiKey = _apiKey;
    if (apiKey == null) return;
    final toResolve = _chats
        .where((c) => c['isGroup'] != true && str(c['id'], '').contains('@lid') && !_resolvedLidPhones.containsKey(str(c['id'], '')))
        .map((c) => str(c['id'], ''))
        .toList();
    if (toResolve.isEmpty) return;
    debugPrint('[Chats] _resolveLidPhonesForCurrentChats: resolving ${toResolve.length} @lid chat(s)');
    const batchSize = 5;
    for (var i = 0; i < toResolve.length; i += batchSize) {
      final batch = toResolve.skip(i).take(batchSize);
      final results = await Future.wait(batch.map((id) async {
        final phone = await WaChatApiService.resolveContactPhone(_sessionName, apiKey, id);
        return MapEntry(id, phone);
      }));
      for (final r in results) {
        if (r.value != null && r.value!.isNotEmpty) _resolvedLidPhones[r.key] = r.value!;
      }
    }
  }

  Future<void> _loadMine() async {
    final myId = ref.read(authProvider).value?.id;
    if (myId == null) return;
    setState(() => _mineLoading = true);
    try {
      await _resolveLidPhonesForCurrentChats();
      final phones = await _fetchLeadPhones({'assigned_to': myId});
      if (mounted) setState(() { _minePhones = phones; _mineLoading = false; _mineFetched = true; });
    } catch (e) {
      if (mounted) {
        setState(() => _mineLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Couldn't load your leads — ${apiErrorMessage(e)}")));
      }
    }
  }

  Future<void> _loadUnassigned() async {
    setState(() => _unassignedLoading = true);
    try {
      await _resolveLidPhonesForCurrentChats();
      final phones = await _fetchLeadPhones({'stage': 'new'}, onlyUnassigned: true);
      if (mounted) setState(() { _unassignedPhones = phones; _unassignedLoading = false; _unassignedFetched = true; });
    } catch (e) {
      if (mounted) {
        setState(() => _unassignedLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Couldn't load unassigned leads — ${apiErrorMessage(e)}")));
      }
    }
  }

  /// Paginates `/leads` (max 100/page) collecting each matching lead's contact phone, capped at
  /// 1000 leads scanned so a very large company can't turn a tab switch into an unbounded fetch.
  Future<Set<String>> _fetchLeadPhones(Map<String, dynamic> query, {bool onlyUnassigned = false}) async {
    final phones = <String>{};
    var page = 1;
    const perPage = 100;
    const scanCap = 1000;
    var scanned = 0;
    while (scanned < scanCap) {
      final res = await Api.raw.get('/leads', queryParameters: {...query, 'per_page': perPage, 'page': page});
      final body = (res.data as Map).cast<String, dynamic>();
      final data = (body['data'] as List?) ?? const [];
      if (data.isEmpty) break;
      for (final l in data.whereType<Map>()) {
        scanned++;
        if (onlyUnassigned && l['assigned_to'] != null) continue;
        final contact = l['contact'] as Map?;
        // Prefer the exact WhatsApp chat id (`wa_id`) when the contact has one — an @lid chat's
        // id isn't phone-derived at all, so phone matching alone would silently miss it. Fall
        // back to a normalised phone match only for contacts without a recorded wa_id.
        final waId = str(contact?['wa_id'], '');
        if (waId.isNotEmpty) {
          phones.add(waId);
        } else {
          final phone = str(contact?['phone'], '');
          if (phone.isNotEmpty) phones.add('phone:${_last10(phone)}');
        }
      }
      final lastPage = (body['last_page'] as num?)?.toInt() ?? page;
      if (page >= lastPage) break;
      page++;
    }
    debugPrint('[Chats] _fetchLeadPhones($query): scanned $scanned lead(s) → ${phones.length} match key(s)');
    return phones;
  }

  @override
  void initState() {
    super.initState();
    _loadChats();
  }

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
      // Surfaced in the body (not just a snackbar) since this can now fire silently on page
      // open via the auto-reconnect below — a toast alone could come and go unnoticed, leaving
      // the user stuck on a dead loading state with no visible explanation.
      setState(() {
        _reconnecting = false;
        _loadingChats = false;
        _authError = true;
        _chatsError = "Couldn't reconnect — ${apiErrorMessage(e)}";
      });
    }
  }

  Future<void> _loadChats({bool force = false}) async {
    final apiKey = _apiKey;
    if (apiKey == null || apiKey.isEmpty) {
      // No gateway key provisioned yet — reconnecting mints the first one, so there's no
      // "kick other clients" risk here (see _autoReconnectTried) and it's safe to always try
      // automatically rather than making the user find and tap "Reconnect WA Chat" themselves.
      if (!_autoReconnectTried) {
        _autoReconnectTried = true;
        await _reconnectApiKey();
        return;
      }
      setState(() {
        _loadingChats = false;
        _authError = true;
        _chatsError = 'No WhatsApp Chat gateway key on this account yet.';
      });
      return;
    }
    final sessionName = _sessionName;
    if (sessionName.isEmpty) {
      setState(() {
        _loadingChats = false;
        _chatsError = 'This session has no gateway id yet — it may still be provisioning. Try again shortly.';
      });
      return;
    }
    final cached = _chatsCache[sessionName];
    if (!force && cached != null && DateTime.now().difference(cached.$2) < _chatsStaleTtl) {
      setState(() { _chats = cached.$1; _loadingChats = false; _chatsError = null; _authError = false; });
      return;
    }

    setState(() { _loadingChats = true; _chatsError = null; _authError = false; });
    try {
      final chats = await WaChatApiService.getChats(sessionName, apiKey);
      chats.sort((a, b) => (num.tryParse('${b['timestamp'] ?? 0}') ?? 0)
          .compareTo(num.tryParse('${a['timestamp'] ?? 0}') ?? 0));
      if (!mounted) return;
      _chatsCache[sessionName] = (chats, DateTime.now());
      setState(() { _chats = chats; _loadingChats = false; });
      _loadPictures(sessionName, apiKey, chats);
    } catch (e) {
      if (!mounted) return;
      // An expired/revoked token surfaces as a 401 from the gateway. Deliberately NOT
      // auto-reconnected — reconnecting revokes the shared key instantly and can kick a
      // concurrently-open web tab with no warning (see the note on _autoReconnectTried above).
      // Show the manual "Reconnect WA Chat" button and let a human decide, matching the web app.
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
        _ChatTab.mine => 'Mine',
        _ChatTab.unassigned => 'Unassigned',
      };

  /// Whether a chat matches one of the lead match-keys collected by [_fetchLeadPhones] — the
  /// exact WhatsApp chat id first (covers contacts recorded with a `wa_id`), then a
  /// normalised-phone fallback using the chat's real phone: the id's own digits for a `@c.us`
  /// chat, or the gateway-resolved number from [_resolveLidPhonesForCurrentChats] for `@lid`
  /// (whose id is an opaque privacy id, not phone-derived — matching on it directly would never
  /// hit a lead recorded by phone number, which is how most leads actually get created).
  /// Groups never match either CRM tab.
  bool _chatMatchesLeads(Rec chat, Set<String> keys) {
    if (chat['isGroup'] == true) return false;
    final chatId = str(chat['id'], '');
    if (keys.contains(chatId)) return true;
    final realPhone = chatId.contains('@lid') ? (_resolvedLidPhones[chatId] ?? '') : chatId.split('@').first;
    if (realPhone.isEmpty) return false;
    return keys.contains('phone:${_last10(realPhone)}');
  }

  void _openChat(Rec chat) {
    final apiKey = _apiKey;
    if (apiKey == null) return;
    final sessionName = _sessionName;
    final chatId = str(chat['id'], '');
    // Best-effort, matching the web's debounced mark-as-read on opening a chat.
    WaChatApiService.markChatRead(sessionName, apiKey, chatId).catchError((_) {});
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => WaSessionChatRoomPage(
        sessionName: sessionName,
        sessionLabel: str(widget.session['display_name'] ?? widget.session['phone'] ?? widget.session['session_name'], sessionName),
        apiKey: apiKey,
        chatId: chatId,
        chatName: str(chat['name'], 'Unknown'),
        isGroup: chat['isGroup'] == true,
        allChats: _chats,
      ),
    // Forced: the user likely just read/sent messages in there, so the cached unread counts and
    // last-message previews are now stale on purpose, not just past their 60s TTL.
    )).then((_) => _loadChats(force: true));
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
      case _ChatTab.mine:
        list = list.where((c) => _chatMatchesLeads(c, _minePhones)).toList();
      case _ChatTab.unassigned:
        list = list.where((c) => _chatMatchesLeads(c, _unassignedPhones)).toList();
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
    final label = str(widget.session['display_name'] ?? widget.session['phone'] ?? widget.session['session_name'], 'Chats');
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        backgroundColor: AppColors.primaryDark,
        elevation: 0,
        title: Text(label, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Search messages',
            icon: const Icon(Icons.search_rounded, color: Colors.white),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => GlobalSearchPage(
                initialSessionId: _sessionName,
                initialSessionLabel: label,
              ),
            )),
          ),
        ],
      ),
      body: Column(
        children: [
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
                    onSelected: (_) {
                      setState(() => _tab = t);
                      if (t == _ChatTab.mine && !_mineFetched && !_mineLoading) _loadMine();
                      if (t == _ChatTab.unassigned && !_unassignedFetched && !_unassignedLoading) _loadUnassigned();
                    },
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          Expanded(child: _chatsBody()),
        ],
      ),
    );
  }

  Widget _chatsBody() {
    if (_loadingChats) return const Center(child: CircularProgressIndicator());
    if ((_tab == _ChatTab.mine && _mineLoading) || (_tab == _ChatTab.unassigned && _unassignedLoading)) {
      return const Center(child: CircularProgressIndicator());
    }
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
                OutlinedButton(onPressed: () => _loadChats(force: true), child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    final chats = _filteredChats;
    if (chats.isEmpty) {
      final message = switch (_tab) {
        _ChatTab.mine => 'No chats assigned to you.',
        _ChatTab.unassigned => 'No unassigned new leads.',
        _ => 'No chats yet',
      };
      return Center(child: Text(message, style: const TextStyle(color: AppColors.textLight)));
    }
    return RefreshIndicator(
      onRefresh: () => _loadChats(force: true),
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
