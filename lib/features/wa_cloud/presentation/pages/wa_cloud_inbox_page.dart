// ignore_for_file: use_build_context_synchronously
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/material.dart';
import 'package:unichat_mobile_app/core/utils/message_label.dart';
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
  // two tabs — every chat I may see, or only those assigned to me — plus two toggles that narrow either one
  static const _tabs = [('all', 'All chats'), ('mine', 'Assigned to me')];

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
  bool _onlyStarred = false;                    // only the chats I starred
  String _state = 'all';                        // status tab inside either main tab: all · unread · read · closed (they add up to All)
  Map<String, dynamic> _stateCounts = {};
  bool _onlyUnassigned = false;   // only meaningful on the All tab
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
        if (_tab == 'all' && _onlyUnassigned) 'unassigned': 1,
        if (_state != 'all') 'state': _state,
        if (_onlyStarred) 'starred': 1,
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
        if (data is Map && data['state_counts'] is Map) _stateCounts = Map<String, dynamic>.from(data['state_counts'] as Map);
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
    if (content is Map && content['template'] != null) return '[Template] ${content['template']}';
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
        // the two tabs: the chosen one is marked by an underline, not a filled block
        Row(children: [
          for (final t in _tabs)
            Expanded(
              child: InkWell(
                onTap: () { setState(() { _tab = t.$1; if (t.$1 == 'mine') _onlyUnassigned = false; }); _load(); },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  decoration: BoxDecoration(border: Border(bottom: BorderSide(color: _tab == t.$1 ? Theme.of(context).colorScheme.primary : Colors.transparent, width: 2.5))),
                  alignment: Alignment.center,
                  child: Text(
                    _counts[t.$1] == null ? t.$2 : '${t.$2}  ${_counts[t.$1]}',
                    style: TextStyle(fontWeight: _tab == t.$1 ? FontWeight.w800 : FontWeight.w500, color: _tab == t.$1 ? null : context.mutedColor),
                  ),
                ),
              ),
            ),
        ]),
        // status tabs inside the open main tab — the chosen one is outlined, not filled
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            children: [
              for (final (key, label) in [('all', 'All'), ('unread', 'Unread'), ('read', 'Read'), ('closed', 'Closed')])
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(_stateCounts[key] == null ? label : '$label ${_stateCounts[key]}', style: TextStyle(fontSize: 12, fontWeight: _state == key ? FontWeight.w700 : FontWeight.w500)),
                    selected: _state == key,
                    showCheckmark: false,
                    backgroundColor: Colors.transparent,
                    selectedColor: Colors.transparent,
                    side: BorderSide(color: _state == key ? Theme.of(context).colorScheme.primary : context.lineColor, width: _state == key ? 1.6 : 1),
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) { setState(() => _state = key); _load(); },
                  ),
                ),
              FilterChip(
                avatar: Icon(_onlyStarred ? Icons.star_rounded : Icons.star_outline_rounded, size: 16, color: const Color(0xFFF59E0B)),
                label: Text(_counts['starred'] != null ? 'Starred ${_counts['starred']}' : 'Starred', style: const TextStyle(fontSize: 12)),
                selected: _onlyStarred,
                showCheckmark: false,
                onSelected: (v) { setState(() => _onlyStarred = v); _load(); },
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: 6),
              if (_tab == 'all')
                FilterChip(
                  label: Text(_counts['unassigned'] != null ? 'Unassigned ${_counts['unassigned']}' : 'Unassigned', style: const TextStyle(fontSize: 12)),
                  selected: _onlyUnassigned,
                  showCheckmark: false,
                  onSelected: (v) { setState(() => _onlyUnassigned = v); _load(); },
                  visualDensity: VisualDensity.compact,
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
    final phone = str(c['phone']);
    return RecordCard(
      // name with the number, so two customers with the same name can be told apart
      title: phone.isEmpty || name == phone ? name : '$name · $phone',
      subtitle: _preview(c),
      leadingIcon: Icons.chat_rounded,
      leadingColor: const Color(0xFF25A9E0),
      trailing: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          if (c['starred'] == true) const Padding(padding: EdgeInsets.only(right: 3), child: Icon(Icons.star_rounded, size: 14, color: Color(0xFFF59E0B))),
          if (str(c['status']) == 'closed') Padding(padding: const EdgeInsets.only(right: 4), child: Icon(Icons.check_circle_outline_rounded, size: 13, color: context.mutedColor)),
          Text(when(c['last_message_at']), style: TextStyle(color: context.mutedColor, fontSize: 11)),
        ]),
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
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => WaCloudThreadPage(conversation: c)));
        _load(); // opening a thread marks it read — refresh the badges
      },
    );
  }
}

/// One WA Cloud conversation (messages + reply). Public so other screens (the Sales home's "my chats") can open it.
class WaCloudThreadPage extends StatefulWidget {
  const WaCloudThreadPage({super.key, required this.conversation});
  final Rec conversation;
  @override
  State<WaCloudThreadPage> createState() => _ThreadPageState();
}

class _ThreadPageState extends State<WaCloudThreadPage> {
  late Rec _conv = widget.conversation;
  List<Rec> _messages = [];
  bool _loading = true;
  bool _sending = false;
  bool _hasMore = false;       // earlier messages exist
  bool _loadingOlder = false;
  bool _windowOpen = true;     // false once 24 h have passed since the customer last wrote — then only an approved template can be sent
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
        _windowOpen = data['window_open'] != false;
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
    try {
      await Api.post('/conversations/$_id/messages', data: {'body': text});
      if (mounted) _reply.clear();
    } catch (e) {
      if (mounted) await _onSendRefused(e);
    }
    if (!mounted) return;
    setState(() => _sending = false);
    _load();   // shows the new message (or the failed one with its reason)
  }

  /// WhatsApp's own refusal after 24 hours ("re-engagement", code 131047) can't be overridden by us or by paying more — only an approved
  /// template is accepted then. Offer exactly that; any other error is just shown.
  Future<void> _onSendRefused(Object e) async {
    final msg = apiErrorMessage(e);
    final closed = (e is DioException && e.response?.data is Map && (e.response!.data as Map)['window_closed'] == true) ||
        msg.contains('24 hours') || msg.toLowerCase().contains('re-engagement');
    if (!closed) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      return;
    }
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('WhatsApp needs a template'),
        content: const Text('More than 24 hours have passed since this customer last wrote, so WhatsApp does not accept a normal message — whatever it costs. An approved template is always accepted and starts the conversation again.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Not now')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Send a template')),
        ],
      ),
    );
    if (go == true && mounted) await _sendTemplate();
  }

  /// Photo / video / audio / document: pick it, then send it (the typed text becomes the caption). Allowed any time — after 24 hours
  /// WhatsApp decides; if it refuses, its reason is shown.
  Future<void> _attach() async {
    final kind = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.photo_camera_rounded), title: const Text('Camera'), onTap: () => Navigator.pop(ctx, 'camera')),
          ListTile(leading: const Icon(Icons.image_rounded), title: const Text('Photo / video from gallery'), onTap: () => Navigator.pop(ctx, 'gallery')),
          ListTile(leading: const Icon(Icons.insert_drive_file_rounded), title: const Text('Document or audio file'), onTap: () => Navigator.pop(ctx, 'file')),
        ]),
      ),
    );
    if (kind == null) return;
    String? path, name;
    if (kind == 'file') {
      final r = await FilePicker.platform.pickFiles();
      path = r?.files.single.path;
      name = r?.files.single.name;
    } else {
      final x = kind == 'camera' ? await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 85) : await ImagePicker().pickMedia();
      path = x?.path;
      name = x?.name;
    }
    if (path == null || !mounted) return;
    setState(() => _sending = true);
    final caption = _reply.text.trim();
    try {
      await Api.raw.post('/conversations/$_id/media', data: FormData.fromMap({'file': await MultipartFile.fromFile(path, filename: name), if (caption.isNotEmpty) 'caption': caption}));
      if (mounted) _reply.clear();
    } catch (e) {
      if (mounted) await _onSendRefused(e);
    }
    if (!mounted) return;
    setState(() => _sending = false);
    _load();
  }

  /// Send an approved template — allowed any time (it is what WhatsApp always accepts, including after the 24-hour window).
  Future<void> _sendTemplate() async {
    final numberId = (_conv['wa_phone_number_id'] as num?)?.toInt();
    final phone = str(_conv['phone']);
    if (numberId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('This chat has no sending number.')));
      return;
    }
    List<Rec> templates;
    try {
      templates = (await Api.list('/templates', query: {'status': 'approved', 'per_page': 100}))
          .where((t) => str(t['status']).toLowerCase() == 'approved' && (t['wa_phone_number_id'] == null || (t['wa_phone_number_id'] as num).toInt() == numberId))
          .toList();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
      return;
    }
    if (!mounted) return;
    final contactId = (_conv['contact_id'] as num?)?.toInt();
    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      builder: (ctx) => _TemplateSheet(templates: templates, numberId: numberId, phone: phone, contactId: contactId),
    );
    if (sent == true) _load();
  }

  Future<void> _toggleStar() async {
    final next = _conv['starred'] != true;
    setState(() => _conv = {..._conv, 'starred': next});
    try {
      await Api.put('/conversations/$_id/star', data: {'starred': next});
    } catch (e) {
      if (!mounted) return;
      setState(() => _conv = {..._conv, 'starred': !next});
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
    }
  }

  Future<void> _closeOrReopen() async {
    final closing = str(_conv['status']) != 'closed';
    final ok = await runAction(context, () => Api.post('/conversations/$_id/${closing ? 'close' : 'reopen'}'), success: closing ? 'Conversation closed. A new message from the customer reopens it.' : 'Conversation reopened.');
    if (ok) setState(() => _conv = {..._conv, 'status': closing ? 'closed' : 'open'});
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
          IconButton(
            tooltip: _conv['starred'] == true ? 'Starred — tap to unstar' : 'Star this chat',
            onPressed: _toggleStar,
            icon: Icon(_conv['starred'] == true ? Icons.star_rounded : Icons.star_outline_rounded, color: _conv['starred'] == true ? const Color(0xFFF59E0B) : null),
          ),
          if (assigned)
            IconButton(
              tooltip: str(_conv['status']) == 'closed' ? 'Reopen conversation' : 'Close conversation',
              onPressed: _closeOrReopen,
              icon: Icon(str(_conv['status']) == 'closed' ? Icons.replay_rounded : Icons.check_circle_outline_rounded),
            ),
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
        if (!_windowOpen)
          Container(
            width: double.infinity,
            color: const Color(0xFFFEF3C7),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: const Text('More than 24 hours since the customer wrote. You can still send a message or a file — WhatsApp may refuse it; if so, use the template button.',
                style: TextStyle(fontSize: 11.5, color: Color(0xFF92400E))),
          ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 8, 8),
            child: Row(children: [
              // attach a photo / video / audio / document, or send an approved template — any time
              IconButton(tooltip: 'Attach', onPressed: _sending ? null : _attach, icon: const Icon(Icons.attach_file_rounded)),
              IconButton(tooltip: 'Send a template', onPressed: _sendTemplate, icon: const Icon(Icons.description_outlined)),
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

String _mediaLabel(String type) => messageTypeLabel(type);

/// Pick an approved template, fill its variables and send it into this chat (POST /conversations/new reuses the thread).
class _TemplateSheet extends StatefulWidget {
  const _TemplateSheet({required this.templates, required this.numberId, required this.phone, this.contactId});
  final List<Rec> templates;
  final int numberId;
  final String phone;
  final int? contactId;
  @override
  State<_TemplateSheet> createState() => _TemplateSheetState();
}

class _TemplateSheetState extends State<_TemplateSheet> {
  Rec? _tpl;
  List<TextEditingController> _vars = [];
  bool _busy = false;

  int _needed(Rec t) {
    final m = RegExp(r'\{\{\s*(\d+)\s*\}\}').allMatches('${t['body'] ?? ''}').map((x) => int.parse(x.group(1)!)).toList();
    return m.isEmpty ? 0 : m.reduce((a, b) => a > b ? a : b);
  }

  void _pick(Rec t) => setState(() {
        _tpl = t;
        for (final c in _vars) { c.dispose(); }
        _vars = List.generate(_needed(t), (_) => TextEditingController());
      });

  @override
  void dispose() {
    for (final c in _vars) { c.dispose(); }
    super.dispose();
  }

  String get _preview => '${_tpl?['body'] ?? ''}'.replaceAllMapped(RegExp(r'\{\{\s*(\d+)\s*\}\}'), (m) {
        final i = int.parse(m.group(1)!) - 1;
        return i < _vars.length && _vars[i].text.trim().isNotEmpty ? _vars[i].text.trim() : m.group(0)!;
      });

  Future<void> _send() async {
    setState(() => _busy = true);
    try {
      await Api.post('/conversations/new', data: {
        'wa_phone_number_id': widget.numberId,
        'phone': widget.phone.replaceAll(RegExp(r'\D'), ''),
        if (widget.contactId != null) 'contact_id': widget.contactId,
        'template_id': (_tpl!['id'] as num).toInt(),
        'variables': _vars.map((c) => c.text.trim()).toList(),
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ready = _tpl != null && _vars.every((c) => c.text.trim().isNotEmpty);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(padding: EdgeInsets.fromLTRB(20, 16, 20, 4), child: Text('Send a template', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
          if (widget.templates.isEmpty)
            const Padding(padding: EdgeInsets.all(20), child: Text('No approved templates for this number yet.'))
          else
            Flexible(
              child: ListView(shrinkWrap: true, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
                for (final t in widget.templates)
                  ListTile(
                    dense: true,
                    leading: Icon(_tpl == t ? Icons.radio_button_checked : Icons.radio_button_unchecked, color: _tpl == t ? Theme.of(context).colorScheme.primary : null),
                    title: Text('${t['name']}', style: TextStyle(fontWeight: _tpl == t ? FontWeight.w700 : FontWeight.w500)),
                    subtitle: Text('${t['body'] ?? ''}', maxLines: 2, overflow: TextOverflow.ellipsis),
                    onTap: () => _pick(t),
                  ),
              ]),
            ),
          if (_tpl != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Container(width: double.infinity, padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: context.altSurface, borderRadius: BorderRadius.circular(10)), child: Text(_preview, style: const TextStyle(fontSize: 13))),
            ),
            for (var i = 0; i < _vars.length; i++)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: TextField(controller: _vars[i], onChanged: (_) => setState(() {}), decoration: InputDecoration(isDense: true, border: const OutlineInputBorder(), labelText: 'Value for {{${i + 1}}}')),
              ),
          ],
          Padding(
            padding: const EdgeInsets.all(20),
            child: SizedBox(width: double.infinity, child: FilledButton(onPressed: ready && !_busy ? _send : null, child: Text(_busy ? 'Sending…' : 'Send template'))),
          ),
        ]),
      ),
    );
  }
}
