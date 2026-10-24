// ignore_for_file: use_build_context_synchronously
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:unichat_mobile_app/features/modules/_shared.dart';
import 'package:unichat_mobile_app/features/wa_cloud/presentation/widgets/inbox_media.dart';

/// WA Cloud team inbox — the same conversations the web `/wa-cloud/inbox` shows, with the
/// Unread / All / Mine / Unassigned tabs.
class WaCloudInboxPage extends StatefulWidget {
  const WaCloudInboxPage({super.key});
  @override
  State<WaCloudInboxPage> createState() => _WaCloudInboxPageState();
}

class _WaCloudInboxPageState extends State<WaCloudInboxPage> {
  static const _tabs = [('unread', 'Unread'), ('all', 'All'), ('mine', 'Mine'), ('unassigned', 'Unassigned')];

  static const _perPage = 30;

  List<Rec> _rows = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  int _page = 1;
  int _total = 0;
  Map<String, dynamic> _counts = {}; // totals for the tabs, from the server
  String? _error;
  String _tab = 'all';
  final _search = TextEditingController();
  final _scroll = ScrollController();
  Timer? _debounce;
  int _reqToken = 0; // a newer tab / search supersedes an older, slower response

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.hasClients && _scroll.position.extentAfter < 300) _loadMore();
    });
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  Map<String, dynamic> _query(int page) => {
        'per_page': _perPage,
        'page': page,
        if (_tab == 'mine') 'mine': 1,
        if (_tab == 'unassigned') 'unassigned': 1,
        if (_tab == 'unread') 'unread': 1,
        if (_search.text.trim().isNotEmpty) 'search': _search.text.trim(),
      };

  List<Rec> _parse(dynamic data) =>
      ((data is Map ? data['conversations'] : null) as List? ?? const []).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();

  /// First page. GET /conversations returns { conversations, total, page, has_more } — not one of the
  /// shapes Api.list unwraps — and search runs on the server so chats beyond the loaded pages are found.
  Future<void> _load() async {
    final token = ++_reqToken;
    setState(() { _loading = true; _error = null; });
    try {
      final res = await Api.raw.get('/conversations', queryParameters: _query(1));
      if (!mounted || token != _reqToken) return;
      final data = res.data;
      final rows = _parse(data);
      setState(() {
        _rows = rows;
        _page = 1;
        _hasMore = data is Map && data['has_more'] == true;
        _total = data is Map ? (num.tryParse('${data['total']}')?.toInt() ?? rows.length) : rows.length;
        if (data is Map && data['counts'] is Map) _counts = Map<String, dynamic>.from(data['counts'] as Map);
        _loading = false;
      });
    } catch (e) {
      if (mounted && token == _reqToken) setState(() { _error = apiErrorMessage(e); _loading = false; });
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasMore) return;
    final token = _reqToken;
    setState(() => _loadingMore = true);
    try {
      final res = await Api.raw.get('/conversations', queryParameters: _query(_page + 1));
      if (!mounted || token != _reqToken) return;
      final data = res.data;
      final more = _parse(data);
      setState(() {
        final seen = _rows.map((c) => c['id']).toSet();
        _rows = [..._rows, ...more.where((c) => !seen.contains(c['id']))];
        _page += 1;
        _hasMore = data is Map && data['has_more'] == true;
        _total = data is Map ? (num.tryParse('${data['total']}')?.toInt() ?? _total) : _total;
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  List<Rec> get _visible => _rows;

  String _preview(Rec c) {
    final last = c['last_message'] ?? c['lastMessage'];
    if (last is! Map) return '';
    final content = last['content'];
    final body = content is Map ? content['body'] : null;
    if (body != null && '$body'.isNotEmpty) return '$body';
    final type = '${last['type'] ?? ''}';
    return type.isNotEmpty && type != 'text' ? _mediaLabel(type) : '';
  }

  @override
  Widget build(BuildContext context) {
    final rows = _visible;
    return Scaffold(
      appBar: AppBar(title: const Text('Inbox')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: TextField(
            controller: _search,
            onChanged: (_) { _debounce?.cancel(); _debounce = Timer(const Duration(milliseconds: 350), _load); },
            decoration: const InputDecoration(isDense: true, hintText: 'Search name or number', prefixIcon: Icon(Icons.search_rounded, size: 20)),
          ),
        ),
        SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            children: [
              for (final t in _tabs)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(_counts[t.$1] == null ? t.$2 : '${t.$2} ${_counts[t.$1]}'),
                    selected: _tab == t.$1,
                    onSelected: (_) { setState(() => _tab = t.$1); _load(); },
                  ),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)))
                  : rows.isEmpty
                      ? Center(child: Text('No conversations', style: TextStyle(color: context.mutedColor)))
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView.separated(
                            controller: _scroll,
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.all(12),
                            itemCount: rows.length + 1,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (_, i) => i < rows.length ? _tile(rows[i]) : _listFooter(rows.length),
                          ),
                        ),
        ),
      ]),
    );
  }

  Widget _listFooter(int shown) {
    if (_hasMore) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Center(
          child: _loadingMore
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
              : OutlinedButton(onPressed: _loadMore, child: Text('Load more · $shown of $_total')),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(child: Text('$shown conversation${shown == 1 ? '' : 's'} · all loaded', style: TextStyle(color: context.mutedColor, fontSize: 12))),
    );
  }

  Widget _tile(Rec c) {
    final contact = c['contact'] is Map ? c['contact'] as Map : const {};
    final name = str(c['contact_name'] ?? contact['name'] ?? c['phone'], 'Unknown');
    final unread = num.tryParse('${c['unread_count'] ?? 0}') ?? 0;
    final agent = c['assigned_agent'] is Map ? c['assigned_agent']['name'] : null;
    final number = c['wa_phone_number'] is Map ? c['wa_phone_number'] as Map : const {};
    return RecordCard(
      title: name,
      subtitle: _preview(c).isEmpty ? str(c['phone']) : _preview(c),
      leadingIcon: Icons.chat_rounded,
      leadingColor: const Color(0xFF25A9E0),
      trailing: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text(when(c['last_message_at']), style: TextStyle(color: context.mutedColor, fontSize: 11)),
        if (unread > 0)
          Container(
            margin: const EdgeInsets.only(top: 4),
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(color: AppPalette.accent, borderRadius: BorderRadius.circular(10)),
            child: Text('${unread.toInt()}', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
          ),
      ]),
      footer: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(
          [if (number['label'] != null || number['display_number'] != null) '${number['label'] ?? number['display_number']}', agent != null ? 'Agent: $agent' : 'Unassigned'].join(' · '),
          style: TextStyle(color: context.mutedColor, fontSize: 11),
        ),
      ),
      onTap: () async {
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => _ThreadPage(conversation: c)));
        _load(); // opening a thread marks it read — refresh the badges
      },
    );
  }
}

class _ThreadPage extends StatefulWidget {
  const _ThreadPage({required this.conversation});
  final Rec conversation;
  @override
  State<_ThreadPage> createState() => _ThreadPageState();
}

class _ThreadPageState extends State<_ThreadPage> {
  late Rec _conv = widget.conversation;
  List<Rec> _messages = [];
  bool _loading = true;
  bool _sending = false;
  bool _hasMore = false;       // earlier messages exist
  bool _loadingOlder = false;
  final _reply = TextEditingController();
  final _scroll = ScrollController();

  int get _id => (widget.conversation['id'] as num).toInt();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (!_scroll.hasClients) return;
      if (_scroll.position.pixels < 80) _loadOlder();
    });
    _load();
  }

  @override
  void dispose() {
    _reply.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// The newest page of the thread (50 messages); earlier ones load on request with `before_id`.
  Future<void> _load() async {
    try {
      final res = await Api.raw.get('/conversations/$_id/messages');
      final data = res.data as Map;
      if (!mounted) return;
      setState(() {
        if (data['conversation'] is Map) _conv = (data['conversation'] as Map).cast<String, dynamic>();
        _messages = ((data['messages'] as List?) ?? const []).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
        _hasMore = data['has_more'] == true;
        _loading = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
      });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
      }
    }
  }

  /// Earlier messages: the page before the oldest one loaded. The reader's place is kept by adding the
  /// height the new rows took to the scroll offset.
  Future<void> _loadOlder() async {
    if (_loadingOlder || _loading || !_hasMore || _messages.isEmpty) return;
    setState(() => _loadingOlder = true);
    final beforeExtent = _scroll.hasClients ? _scroll.position.maxScrollExtent : 0.0;
    final beforePixels = _scroll.hasClients ? _scroll.position.pixels : 0.0;
    try {
      final res = await Api.raw.get('/conversations/$_id/messages', queryParameters: {'before_id': _messages.first['id']});
      final data = res.data as Map;
      if (!mounted) return;
      final older = ((data['messages'] as List?) ?? const []).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
      setState(() {
        final seen = _messages.map((m) => m['id']).toSet();
        _messages = [...older.where((m) => !seen.contains(m['id'])), ..._messages];
        _hasMore = data['has_more'] == true;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.jumpTo(beforePixels + (_scroll.position.maxScrollExtent - beforeExtent));
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
    } finally {
      if (mounted) setState(() => _loadingOlder = false);
    }
  }

  Future<void> _send() async {
    final text = _reply.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    final ok = await runAction(context, () => Api.post('/conversations/$_id/messages', data: {'body': text}));
    if (!mounted) return;
    setState(() => _sending = false);
    if (ok) { _reply.clear(); _load(); }
  }

  Future<void> _claimOrRelease(bool claim) async {
    final ok = await runAction(context, () => Api.post('/conversations/$_id/${claim ? 'claim' : 'release'}'),
        success: claim ? 'Conversation claimed.' : 'Released.');
    if (ok) _load();
  }

  String _text(Rec m) {
    final c = m['content'];
    if (c is Map) {
      final body = c['body'] ?? c['text'] ?? c['caption'];
      if (body != null && '$body'.isNotEmpty) return '$body';
      if (c['template'] != null) return '[Template] ${c['template']}';
    }
    final t = '${m['type'] ?? ''}';
    return t.isEmpty || t == 'text' ? '' : _mediaLabel(t);
  }

  @override
  Widget build(BuildContext context) {
    final contact = _conv['contact'] is Map ? _conv['contact'] as Map : const {};
    final name = str(_conv['contact_name'] ?? contact['name'] ?? _conv['phone'], 'Chat');
    final assigned = _conv['assigned_to'] != null;
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          Text(str(_conv['phone']), style: const TextStyle(fontSize: 11)),
        ]),
        actions: [
          if (!assigned) TextButton(onPressed: () => _claimOrRelease(true), child: const Text('Claim')),
          if (assigned) TextButton(onPressed: () => _claimOrRelease(false), child: const Text('Release')),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _messages.isEmpty
                  ? Center(child: Text('No messages', style: TextStyle(color: context.mutedColor)))
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.all(12),
                      itemCount: _messages.length + 1,
                      itemBuilder: (_, i) {
                        if (i == 0) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Center(
                              child: _hasMore
                                  ? (_loadingOlder
                                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                                      : TextButton(onPressed: _loadOlder, child: const Text('↑ Load earlier messages')))
                                  : Text('Start of conversation', style: TextStyle(color: context.mutedColor, fontSize: 11)),
                            ),
                          );
                        }
                        return _bubble(_messages[i - 1]);
                      },
                    ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 8, 8),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _reply,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.newline,
                  decoration: const InputDecoration(isDense: true, hintText: 'Type a reply…'),
                ),
              ),
              IconButton(
                onPressed: _sending ? null : _send,
                icon: _sending
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.send_rounded),
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _bubble(Rec m) {
    final out = m['direction'] == 'outbound';
    final failed = m['status'] == 'failed';
    final text = _text(m);
    final c = m['content'];
    final media = c is Map && c['media'] is Map ? c['media'] as Map : null;
    final mediaType = '${m['type'] ?? ''}';
    final hasMedia = media != null && '${media['url'] ?? ''}'.isNotEmpty;
    final textColor = Theme.of(context).colorScheme.onSurface;
    return Align(
      alignment: out ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: out ? AppPalette.accent.withValues(alpha: 0.14) : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: failed ? AppPalette.danger : context.lineColor),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (hasMedia) InboxMedia(type: mediaType, media: media, textColor: textColor),
          if (hasMedia && text.isNotEmpty) const SizedBox(height: 6),
          if (text.isNotEmpty) Text(text),
          const SizedBox(height: 3),
          Text(
            '${when(m['created_at'])}${out ? ' · ${str(m['status'], 'sent')}' : ''}',
            style: TextStyle(color: context.mutedColor, fontSize: 10),
          ),
          if (failed && str(m['failure_reason'], '').isNotEmpty)
            Text('Failed: ${m['failure_reason']}', style: const TextStyle(color: AppPalette.danger, fontSize: 11)),
        ]),
      ),
    );
  }
}

String _mediaLabel(String type) => switch (type) {
      'image' => 'Photo',
      'video' => 'Video',
      'audio' => 'Voice message',
      'document' => 'Document',
      'sticker' => 'Sticker',
      'location' => 'Location',
      _ => '[$type]',
    };
