import 'package:flutter/material.dart';
import 'package:unichat_mobile_app/core/constants/app_colors.dart';
import 'package:unichat_mobile_app/core/network/wa_chat_api_service.dart';
import 'package:unichat_mobile_app/core/widgets/app_avatar.dart';
import 'package:unichat_mobile_app/core/widgets/whatsapp_bubble.dart';
import 'package:unichat_mobile_app/features/modules/_shared.dart';
import '../widgets/wa_attachment_sheet.dart';
import 'contact_info_page.dart';

const _quickReactions = ['👍', '❤️', '😂', '😮', '😢', '🙏'];

/// One WA Chat session's conversation thread — message history, send, reply, react, delete
/// and forward, all straight against the gateway (mirrors messageApi in
/// frontend/src/pages/wa-chat/api/api.ts). [allChats] is the session's own chat list, reused
/// here only to offer as forward targets without a second network round trip.
class WaSessionChatRoomPage extends StatefulWidget {
  const WaSessionChatRoomPage({
    super.key,
    required this.sessionName,
    required this.sessionLabel,
    required this.apiKey,
    required this.chatId,
    required this.chatName,
    required this.isGroup,
    required this.allChats,
  });

  final String sessionName;
  /// Friendly display name for [sessionName] (falls back to the raw id) — shown in the app bar so
  /// it's clear which WA session this conversation is on, matching Chats.tsx's ChatRoom header.
  final String sessionLabel;
  final String apiKey;
  final String chatId;
  final String chatName;
  final bool isGroup;
  final List<Rec> allChats;

  @override
  State<WaSessionChatRoomPage> createState() => _WaSessionChatRoomPageState();
}

class _WaSessionChatRoomPageState extends State<WaSessionChatRoomPage> {
  final _scroll = ScrollController();
  final _input = TextEditingController();
  // Raw DB rows (newest first, as the gateway returns them) and the mapped engine-history
  // backfill, kept separate from [_messages] (the merged, ascending list the thread renders) so
  // "load older" can re-page just the DB side without redoing the merge from scratch each time.
  List<Rec> _dbMessages = [];
  List<Rec> _historyMessages = [];
  List<Rec> _messages = [];
  bool _loading = true;
  String? _error;
  bool _sending = false;
  Rec? _replyingTo;

  // Pagination — `total` from the DB endpoint's last response tells us whether more history is
  // left to page in via the `after` keyset cursor (see WaChatApiService.getChatMessagesPage).
  int? _dbTotal;
  bool _loadingMore = false;

  String? _pictureUrl;

  static const _pageSize = 30;

  @override
  void initState() {
    super.initState();
    _load();
    if (!widget.isGroup) _loadPicture();
    _scroll.addListener(_onScroll);
  }

  /// Auto-loads the next older page once the user scrolls near the top of the (ascending) list —
  /// replaces a manual "Load older" tap with the scroll-triggered behavior WhatsApp itself uses.
  void _onScroll() {
    if (!_scroll.hasClients || _loadingMore || _loading) return;
    if (_hasMoreHistory && _scroll.position.pixels <= 200) {
      _loadMore();
    }
  }

  Future<void> _loadPicture() async {
    final url = await WaChatApiService.getContactProfilePicture(widget.sessionName, widget.apiKey, widget.chatId);
    if (mounted && url != null) setState(() => _pictureUrl = url);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _input.dispose();
    super.dispose();
  }

  /// Mirrors `useChatMessages.ts` exactly: the DB endpoint alone only has what the gateway
  /// happened to capture live (a fresh session, or one that reconnected after downtime, has gaps
  /// or is missing everything before that point) — fetch the engine's own live history too and
  /// merge, or messages the DB never persisted just silently don't show up.
  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    Object? dbError;
    // Fired together, not one-after-the-other — awaiting the DB call before even starting the
    // history call was doubling the wall-clock wait for no reason, since neither depends on the
    // other's result. Both futures start their network call the moment they're created here.
    final dbFuture = WaChatApiService
        .getChatMessagesPage(widget.sessionName, widget.apiKey, widget.chatId, limit: _pageSize)
        .then<Map<String, dynamic>?>((v) => v)
        .catchError((e) { dbError = e; return null; });
    final historyFuture = WaChatApiService
        .getChatHistory(widget.sessionName, widget.apiKey, widget.chatId, limit: _pageSize)
        .then<List<Map<String, dynamic>>?>((v) => v)
        // Best-effort backfill — the DB slice above is still shown if this fails.
        .catchError((_) => null);
    final dbPage = await dbFuture;
    final historyRaw = await historyFuture;
    if (!mounted) return;
    if (dbPage == null && historyRaw == null) {
      setState(() { _error = apiErrorMessage(dbError!); _loading = false; });
      return;
    }
    _dbMessages = (dbPage?['messages'] as List?)?.cast<Rec>() ?? const [];
    final total = dbPage?['total'];
    _dbTotal = total is num ? total.toInt() : null;
    _historyMessages = (historyRaw ?? const []).map(_mapHistoryMessage).toList();
    setState(() { _messages = _mergeMessages(_dbMessages, _historyMessages); _loading = false; });
    _scrollToBottom();
  }

  /// Whether more DB history remains beyond what's already fetched — the `after` cursor above the
  /// message list only renders while this is true (or unknown, e.g. the very first page failed to
  /// report a total).
  bool get _hasMoreHistory => _dbTotal == null || _dbMessages.length < _dbTotal!;

  /// Pages in the next-older slice of DB messages via the keyset cursor (the `id` of the oldest
  /// DB row already fetched — a history-backfill row can't be used here, it was never a DB row).
  Future<void> _loadMore() async {
    if (_dbMessages.isEmpty || _loadingMore) return;
    final cursor = str(_dbMessages.last['id'], '');
    if (cursor.isEmpty) return;
    setState(() => _loadingMore = true);
    try {
      final page = await WaChatApiService.getChatMessagesPage(
          widget.sessionName, widget.apiKey, widget.chatId, after: cursor, limit: _pageSize);
      final older = (page['messages'] as List?)?.cast<Rec>() ?? const [];
      final total = page['total'];
      if (!mounted) return;
      setState(() {
        _dbMessages = [..._dbMessages, ...older];
        if (total is num) _dbTotal = total.toInt();
        _messages = _mergeMessages(_dbMessages, _historyMessages);
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Couldn't load older messages — ${apiErrorMessage(e)}")));
    }
  }

  /// Mirrors `mapEngineHistoryMessage` — normalizes a live-engine history row into the same shape
  /// as a DB message row so both can merge into one thread.
  static const _historyMediaTypes = {'image', 'video', 'audio', 'voice', 'sticker', 'document'};

  Rec _mapHistoryMessage(Rec h) {
    final type = str(h['type'], 'unknown');
    final ts = (num.tryParse('${h['timestamp'] ?? 0}') ?? 0).toInt();
    final media = h['media'];
    final quotedMessage = h['quotedMessage'];
    final location = h['location'];
    // Unlike the frontend's own mapEngineHistoryMessage (which drops these two), carry them
    // through — a reply-quote or location message backfilled from history otherwise renders as
    // bare, contentless body text with no indication of what it actually was.
    final metadata = <String, dynamic>{
      if (media != null)
        'media': media
      else if (_historyMediaTypes.contains(type))
        'media': {'mimetype': '', 'omitted': true},
      if (quotedMessage != null) 'quotedMessage': quotedMessage,
      if (location != null) 'location': location,
    };
    return {
      'id': h['id'],
      'waMessageId': h['id'],
      'chatId': h['chatId'],
      'chatName': h['contact']?['pushName'] ?? h['contact']?['name'],
      'author': h['author'],
      'from': h['from'],
      'to': h['to'],
      'body': h['body'] ?? '',
      'type': type,
      'direction': h['fromMe'] == true ? 'outgoing' : 'incoming',
      // Historical messages have no live delivery state — they're old/already-seen.
      'status': 'read',
      'timestamp': ts,
      'createdAt': DateTime.fromMillisecondsSinceEpoch(ts * 1000, isUtc: true).toIso8601String(),
      if (metadata.isNotEmpty) 'metadata': metadata,
    };
  }

  static String _msgKey(Rec m) => str(m['waMessageId'] ?? m['id'], '');

  static num _msgTime(Rec m) {
    final ts = m['timestamp'];
    if (ts is num) return ts;
    final created = DateTime.tryParse(str(m['createdAt'], ''));
    return created == null ? 0 : created.millisecondsSinceEpoch ~/ 1000;
  }

  /// Mirrors `mergeChatMessages` — dedupes by the WhatsApp message id (engine `id` == DB
  /// `waMessageId`); the DB copy wins on conflict (it carries the real delivery status), but
  /// salvages the history copy's `author` when the DB row (a legacy one) has none, so two
  /// same-named group participants don't collapse into one attribution run.
  List<Rec> _mergeMessages(List<Rec> db, List<Rec> history) {
    final byId = <String, Rec>{};
    for (final m in history) {
      byId[_msgKey(m)] = m;
    }
    for (final m in db) {
      final key = _msgKey(m);
      final hist = byId[key];
      byId[key] = (hist != null && hist['author'] != null && m['author'] == null)
          ? {...m, 'author': hist['author']}
          : m;
    }
    final sorted = byId.values.toList()
      ..sort((a, b) {
        final byTime = _msgTime(a).compareTo(_msgTime(b));
        return byTime != 0 ? byTime : str(a['createdAt'], '').compareTo(str(b['createdAt'], ''));
      });
    return sorted;
  }

  Future<void> _openAttachmentSheet() async {
    final sent = await showWaAttachmentSheet(context,
        sessionName: widget.sessionName, apiKey: widget.apiKey, chatId: widget.chatId);
    if (sent) await _load();
  }

  void _openContactInfo() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ContactInfoPage(
        sessionName: widget.sessionName,
        apiKey: widget.apiKey,
        chatId: widget.chatId,
        chatName: widget.chatName,
      ),
    ));
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    _input.clear();
    setState(() => _sending = true);
    try {
      final quoted = _replyingTo;
      if (quoted != null) {
        await WaChatApiService.reply(widget.sessionName, widget.apiKey,
            chatId: widget.chatId, quotedMessageId: str(quoted['id'], ''), text: text);
      } else {
        await WaChatApiService.sendText(widget.sessionName, widget.apiKey, widget.chatId, text);
      }
      if (mounted) setState(() => _replyingTo = null);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Send failed: ${apiErrorMessage(e)}')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _react(Rec message, String emoji) async {
    try {
      await WaChatApiService.react(widget.sessionName, widget.apiKey,
          chatId: widget.chatId, messageId: str(message['id'], ''), emoji: emoji);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
      }
    }
  }

  Future<void> _delete(Rec message) async {
    if (!await confirm(context, title: 'Delete message?', destructive: true, confirmLabel: 'Delete')) return;
    try {
      await WaChatApiService.deleteMessage(widget.sessionName, widget.apiKey,
          chatId: widget.chatId, messageId: str(message['id'], ''));
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
      }
    }
  }

  Future<void> _forward(Rec message) async {
    final targets = widget.allChats.where((c) => str(c['id'], '') != widget.chatId).toList();
    if (targets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No other chats to forward to.')));
      return;
    }
    final target = await showModalBottomSheet<Rec>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Text('Forward to…', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            ),
            ...targets.map((c) => ListTile(
                  leading: AppAvatar(name: str(c['name'], '?'), size: 36),
                  title: Text(str(c['name'], 'Unknown')),
                  onTap: () => Navigator.pop(ctx, c),
                )),
          ],
        ),
      ),
    );
    if (target == null) return;
    try {
      await WaChatApiService.forward(widget.sessionName, widget.apiKey,
          fromChatId: widget.chatId, toChatId: str(target['id'], ''), messageId: str(message['id'], ''));
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Forwarded to ${str(target['name'], 'chat')}.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
      }
    }
  }

  void _showMessageActions(Rec message, bool fromMe) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Wrap(
                spacing: 12,
                children: _quickReactions
                    .map((e) => InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () { Navigator.pop(ctx); _react(message, e); },
                          child: Padding(
                            padding: const EdgeInsets.all(6),
                            child: Text(e, style: const TextStyle(fontSize: 24)),
                          ),
                        ))
                    .toList(),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.reply_rounded),
              title: const Text('Reply'),
              onTap: () { Navigator.pop(ctx); setState(() => _replyingTo = message); },
            ),
            ListTile(
              leading: const Icon(Icons.forward_rounded),
              title: const Text('Forward'),
              onTap: () { Navigator.pop(ctx); _forward(message); },
            ),
            if (fromMe)
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded, color: AppColors.error),
                title: const Text('Delete', style: TextStyle(color: AppColors.error)),
                onTap: () { Navigator.pop(ctx); _delete(message); },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgLight,
      appBar: AppBar(
        backgroundColor: AppColors.primaryDark,
        title: InkWell(
          onTap: widget.isGroup ? null : _openContactInfo,
          child: Row(
            children: [
              AppAvatar(name: widget.chatName, imageUrl: _pictureUrl, size: 36),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.chatName,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
                    Text('📱 ${widget.sessionLabel}${widget.isGroup ? ' · Group' : ''}',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, color: Colors.white60)),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          if (!widget.isGroup)
            IconButton(
              icon: const Icon(Icons.info_outline_rounded),
              tooltip: 'Contact info',
              onPressed: _openContactInfo,
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text("Couldn't load messages — $_error"))
                    : _messages.isEmpty
                        ? const Center(child: Text('No messages yet', style: TextStyle(color: AppColors.textLight)))
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.builder(
                              controller: _scroll,
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              itemCount: _messages.length + (_hasMoreHistory ? 1 : 0),
                              itemBuilder: (_, i) {
                                if (_hasMoreHistory && i == 0) {
                                  // Loading is scroll-triggered (see _onScroll) — this row is just
                                  // the spinner while that fetch is in flight, not a tap target.
                                  return _loadingMore
                                      ? const Center(
                                          child: Padding(
                                            padding: EdgeInsets.symmetric(vertical: 10),
                                            child: SizedBox(
                                                width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                                          ),
                                        )
                                      : const SizedBox.shrink();
                                }
                                final m = _messages[i - (_hasMoreHistory ? 1 : 0)];
                                final fromMe = m['direction'] == 'outgoing';
                                return GestureDetector(
                                  onLongPress: () => _showMessageActions(m, fromMe),
                                  child: WhatsAppBubble(message: _bubbleData(m), isSent: fromMe),
                                );
                              },
                            ),
                          ),
          ),
          if (_replyingTo != null) _replyBanner(),
          _inputBar(),
        ],
      ),
    );
  }

  /// [WhatsAppBubble] expects a Laravel-style `ack` int; the gateway's `status` is a string
  /// (`pending|sent|delivered|read|failed`) — map it rather than change the shared widget.
  Map<String, dynamic> _bubbleData(Rec m) {
    const ackByStatus = {'pending': 0, 'sent': 1, 'delivered': 2, 'read': 3, 'failed': 0};
    return {...m, 'ack': ackByStatus[str(m['status'], '')] ?? 0};
  }

  Widget _replyBanner() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Container(width: 3, height: 32, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Replying to', style: TextStyle(fontSize: 11, color: AppColors.textLight)),
                Text(str(_replyingTo?['body'], ''), maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 18),
            onPressed: () => setState(() => _replyingTo = null),
          ),
        ],
      ),
    );
  }

  Widget _inputBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            IconButton(
              onPressed: _openAttachmentSheet,
              icon: const Icon(Icons.attach_file_rounded, color: AppColors.textLight),
            ),
            Expanded(
              child: TextField(
                controller: _input,
                onSubmitted: (_) => _send(),
                decoration: const InputDecoration(
                  hintText: 'Type a message',
                  hintStyle: TextStyle(color: AppColors.textLight),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(horizontal: 4),
                ),
                maxLines: 4,
                minLines: 1,
              ),
            ),
            _sending
                ? const SizedBox(width: 40, height: 40, child: CircularProgressIndicator(strokeWidth: 2))
                : GestureDetector(
                    onTap: _send,
                    child: Container(
                      width: 40, height: 40,
                      decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                      child: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}
