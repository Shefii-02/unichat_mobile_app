import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:unichat_mobile_app/core/network/api.dart';
import 'package:unichat_mobile_app/core/socket/socket_service.dart';
import 'package:unichat_mobile_app/core/storage/secure_storage.dart';
import 'package:unichat_mobile_app/features/team_chat/team_api.dart';
import 'package:unichat_mobile_app/features/auth/presentation/providers/auth_provider.dart';

/// Paged list of the caller's chats (direct + groups), newest activity first.
class TeamChatsState {
  const TeamChatsState({
    this.items = const [],
    this.page = 1,
    this.hasMore = false,
    this.loading = true,
    this.loadingMore = false,
    this.error,
    this.unreadTotal = 0,
    this.query = '',
    this.type = 'all',
    this.counts = const {},
  });
  final List<Map<String, dynamic>> items;
  final int page;
  final bool hasMore, loading, loadingMore;
  final String? error;
  final int unreadTotal;
  /// 'all' | 'direct' | 'group' | 'unread'
  final String query, type;
  /// Tab badges from the server: unread_chats, direct_unread, group_unread, mentions (across ALL chats).
  final Map<String, int> counts;
  int count(String k) => counts[k] ?? 0;

  TeamChatsState copyWith({
    List<Map<String, dynamic>>? items, int? page, bool? hasMore, bool? loading, bool? loadingMore,
    String? error, bool clearError = false, int? unreadTotal, String? query, String? type, Map<String, int>? counts,
  }) =>
      TeamChatsState(
        items: items ?? this.items, page: page ?? this.page, hasMore: hasMore ?? this.hasMore,
        loading: loading ?? this.loading, loadingMore: loadingMore ?? this.loadingMore,
        error: clearError ? null : (error ?? this.error), unreadTotal: unreadTotal ?? this.unreadTotal,
        query: query ?? this.query, type: type ?? this.type, counts: counts ?? this.counts,
      );
}

class TeamChatsNotifier extends Notifier<TeamChatsState> {
  static const _perPage = 30;
  int _gen = 0; // bumped on every reset so a slow, stale response can never overwrite a newer list

  @override
  TeamChatsState build() {
    Future.microtask(reload);
    return const TeamChatsState();
  }

  Future<({List<Map<String, dynamic>> items, bool hasMore, int unread, Map<String, int> counts})> _fetch(int page) async {
    final d = await TeamApi.page('/team-chat/chats', query: {
      'page': page,
      'per_page': _perPage,
      if (state.query.isNotEmpty) 'q': state.query,
      if (state.type == 'direct' || state.type == 'group') 'type': state.type,
      if (state.type == 'unread') 'filter': 'unread',
    });
    final rows = (d['data'] is List ? d['data'] as List : const []).whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
    final c = d['counts'] is Map ? d['counts'] as Map : const {};
    return (
      items: rows,
      hasMore: d['has_more'] == true,
      unread: (d['unread_total'] as num?)?.toInt() ?? 0,
      counts: {for (final e in c.entries) '${e.key}': (e.value as num?)?.toInt() ?? 0},
    );
  }

  /// Fresh first page (pull-to-refresh, filter / search change).
  Future<void> reload() async {
    final gen = ++_gen;
    state = state.copyWith(loading: state.items.isEmpty, clearError: true, page: 1);
    try {
      final r = await _fetch(1);
      if (gen != _gen) return;
      state = state.copyWith(items: r.items, hasMore: r.hasMore, loading: false, loadingMore: false, page: 1, unreadTotal: r.unread, counts: r.counts);
    } catch (e) {
      if (gen != _gen) return;
      state = state.copyWith(loading: false, loadingMore: false, error: apiErrorMessage(e));
    }
  }

  /// The chat whose room is on screen (set by the room page): its new messages are read on arrival, so they must not
  /// bump the unread badge.
  static int? openChatId;

  /// A live `message` event: update the list row straight from the event (move to top, last message, unread) — no
  /// REST call, so the receiver sees it as fast as the socket delivers it. Returns false when the chat isn't in the
  /// loaded list (a brand-new chat) so the caller can fall back to one refresh.
  bool applyIncoming(Map<String, dynamic> e, {required int me}) {
    final msg = e['message'];
    final chatId = (e['chat_id'] as num?)?.toInt();
    if (msg is! Map || chatId == null) return false;
    final i = state.items.indexWhere((c) => (c['id'] as num?)?.toInt() == chatId);
    if (i < 0) return false;
    final mineMsg = msg['mine'] == true || (e['by'] as num?)?.toInt() == me;
    final unreadIt = !mineMsg && openChatId != chatId;
    final mentioned = unreadIt && ((msg['mentions'] as List?)?.any((x) => (x as num?)?.toInt() == me) ?? false);
    final c = Map<String, dynamic>.from(state.items[i])
      ..['last_message'] = _previewOf(msg)
      ..['last_sender'] = msg['sender_name']
      ..['last_message_at'] = msg['created_at']
      ..['unread'] = ((c0(state.items[i], 'unread')) + (unreadIt ? 1 : 0))
      ..['unread_mentions'] = ((c0(state.items[i], 'unread_mentions')) + (mentioned ? 1 : 0));
    final items = [c, ...state.items.where((x) => x != state.items[i])];
    state = state.copyWith(items: items, unreadTotal: state.unreadTotal + (unreadIt ? 1 : 0));
    return true;
  }

  static int c0(Map c, String k) => (c[k] as num?)?.toInt() ?? 0;

  static String _previewOf(Map m) {
    switch (m['type']) {
      case 'image': return '📷 Photo';
      case 'video': return '🎥 Video';
      case 'audio': return '🎤 Voice message';
      case 'file': return '📎 ${m['attachment_name'] ?? 'File'}';
      case 'location': return '📍 Location';
      case 'contact': return '👤 ${m['contact_name'] ?? 'Contact'}';
    }
    return '${m['body'] ?? ''}';
  }

  bool _refreshing = false, _again = false;
  Timer? _debounce;

  /// For bursts of socket events (every read / delivered / reaction from every member fires one): wait a beat,
  /// then do ONE refresh instead of one per event.
  void scheduleRefresh([Duration wait = const Duration(milliseconds: 400)]) {
    _debounce?.cancel();
    _debounce = Timer(wait, refresh);
  }

  /// Quiet update after a socket event / action: refresh page 1 and keep the older pages already loaded.
  /// Never overlaps itself — a call made while one is running just asks for one more pass afterwards.
  Future<void> refresh() async {
    if (_refreshing) { _again = true; return; }
    _refreshing = true;
    try {
      do {
        _again = false;
        await _refreshOnce();
      } while (_again);
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _refreshOnce() async {
    final gen = _gen;
    try {
      final r = await _fetch(1);
      if (gen != _gen) return;
      final fresh = {for (final c in r.items) c['id']};
      final tail = state.items.where((c) => !fresh.contains(c['id'])).toList();
      state = state.copyWith(
        items: [...r.items, ...tail],
        hasMore: state.page > 1 ? state.hasMore : r.hasMore,
        unreadTotal: r.unread,
        counts: r.counts,
        clearError: true,
        loading: false,
      );
    } catch (_) {/* keep what we have; the next event retries */}
  }

  Future<void> loadMore() async {
    if (state.loading || state.loadingMore || !state.hasMore) return;
    final gen = _gen;
    final next = state.page + 1;
    state = state.copyWith(loadingMore: true);
    try {
      final r = await _fetch(next);
      if (gen != _gen) return;
      final have = {for (final c in state.items) c['id']};
      state = state.copyWith(
        items: [...state.items, ...r.items.where((c) => !have.contains(c['id']))],
        page: next, hasMore: r.hasMore, loadingMore: false, unreadTotal: r.unread, counts: r.counts,
      );
    } catch (_) {
      if (gen == _gen) state = state.copyWith(loadingMore: false);
    }
  }

  void setQuery(String q) {
    if (q == state.query) return;
    state = state.copyWith(query: q);
    reload();
  }

  /// Tab switch: all | direct | group | unread (server-side, so counts and paging stay correct).
  void setType(String t) {
    if (t == state.type) return;
    state = state.copyWith(type: t);
    reload();
  }
}

final teamChatsProvider = NotifierProvider<TeamChatsNotifier, TeamChatsState>(TeamChatsNotifier.new);

/// Everyone in the company a chat can be started with.
final teamUsersProvider = FutureProvider<List<Map<String, dynamic>>>(
    (ref) => TeamApi.list('/team-chat/users'));

/// Total unread across ALL chats (server-computed, so it's right even when only page 1 is loaded).
final teamUnreadProvider = Provider<int>((ref) => ref.watch(teamChatsProvider.select((s) => s.unreadTotal)));

/// Keeps the staff socket connected while signed in and refreshes the chat list on every
/// `team_chat` event (and once on every socket reconnect). Watched by MainShell so it lives for the
/// whole session. No polling — updates are socket-event driven.
final teamChatRealtimeProvider = Provider<void>((ref) {
  final user = ref.watch(authProvider).value;
  if (user == null) return;

  Future<void> connect() async {
    final token = await SecureStorageService.getToken();
    if (token != null) SocketService().connect(token, user.id, user.companyId);
  }

  connect();
  final sub = SocketService().teamChatEvents.listen((e) {
    final chats = ref.read(teamChatsProvider.notifier);
    // A new message carries the whole message: patch the list from it instantly. Everything else (read ticks,
    // reactions, new chats…) just needs one quiet refresh.
    if (e['kind'] != 'message' || !chats.applyIncoming(e, me: user.id)) chats.scheduleRefresh();
    // A message from someone else reached this device → tell the sender (their ticks turn ✓✓).
    if (e['kind'] == 'message' && (e['by'] as num?)?.toInt() != user.id) {
      markChatDelivered((e['chat_id'] as num).toInt());
    }
  });
  final conn = SocketService().connectionState.listen((up) { if (up) ref.read(teamChatsProvider.notifier).refresh(); });
  ref.onDispose(() { sub.cancel(); conn.cancel(); });
});

/// Socket-first "delivered" receipt for a chat (REST fallback). Fire and forget.
Future<void> markChatDelivered(int chatId) async {
  try {
    final r = await SocketService().call('chat:delivered', {'chat_id': chatId});
    if (r == null) await TeamApi.post('/team-chat/chats/$chatId/delivered');
  } catch (_) {}
}

String teamTime(Object? iso) {
  final d = DateTime.tryParse('${iso ?? ''}')?.toLocal();
  if (d == null) return '';
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return '$h:${d.minute.toString().padLeft(2, '0')} ${d.hour >= 12 ? 'PM' : 'AM'}';
}

String teamDay(Object? iso) {
  final d = DateTime.tryParse('${iso ?? ''}')?.toLocal();
  if (d == null) return '';
  final n = DateTime.now();
  final today = DateTime(n.year, n.month, n.day);
  final that = DateTime(d.year, d.month, d.day);
  final diff = today.difference(that).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${d.day} ${m[d.month - 1]} ${d.year}';
}
