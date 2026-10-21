// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:unichat_mobile_app/features/modules/_shared.dart';

/// WA Cloud team inbox — the same conversations the web `/wa-cloud/inbox` shows, with the
/// Unread / All / Mine / Unassigned tabs.
class WaCloudInboxPage extends StatefulWidget {
  const WaCloudInboxPage({super.key});
  @override
  State<WaCloudInboxPage> createState() => _WaCloudInboxPageState();
}

class _WaCloudInboxPageState extends State<WaCloudInboxPage> {
  static const _tabs = [('unread', 'Unread'), ('all', 'All'), ('mine', 'Mine'), ('unassigned', 'Unassigned')];

  List<Rec> _rows = [];
  bool _loading = true;
  String? _error;
  String _tab = 'all';
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      // GET /conversations returns { conversations: [...], total } — not one of the shapes Api.list unwraps.
      final res = await Api.raw.get('/conversations', queryParameters: {
        'per_page': 50,
        if (_tab == 'mine') 'mine': 1,
        if (_tab == 'unassigned') 'unassigned': 1,
        if (_tab == 'unread') 'unread': 1,
      });
      final list = (res.data is Map ? res.data['conversations'] : null) as List? ?? const [];
      if (mounted) {
        setState(() {
          _rows = list.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _error = apiErrorMessage(e); _loading = false; });
    }
  }

  List<Rec> get _visible {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return _rows;
    return _rows.where((c) {
      final name = '${c['contact_name'] ?? (c['contact'] is Map ? c['contact']['name'] : '') ?? ''}'.toLowerCase();
      return name.contains(q) || '${c['phone'] ?? ''}'.toLowerCase().contains(q);
    }).toList();
  }

  String _preview(Rec c) {
    final last = c['last_message'] ?? c['lastMessage'];
    if (last is! Map) return '';
    final content = last['content'];
    final body = content is Map ? content['body'] : null;
    if (body != null && '$body'.isNotEmpty) return '$body';
    final type = '${last['type'] ?? ''}';
    return type.isNotEmpty && type != 'text' ? '[$type]' : '';
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
            onChanged: (_) => setState(() {}),
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
                    label: Text(t.$2),
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
                            padding: const EdgeInsets.all(12),
                            itemCount: rows.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (_, i) => _tile(rows[i]),
                          ),
                        ),
        ),
      ]),
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
  final _reply = TextEditingController();
  final _scroll = ScrollController();

  int get _id => (widget.conversation['id'] as num).toInt();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _reply.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res = await Api.raw.get('/conversations/$_id/messages');
      final data = res.data as Map;
      if (!mounted) return;
      setState(() {
        if (data['conversation'] is Map) _conv = (data['conversation'] as Map).cast<String, dynamic>();
        _messages = ((data['messages'] as List?) ?? const []).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
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
    return t.isEmpty || t == 'text' ? '' : '[$t]';
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
                      itemCount: _messages.length,
                      itemBuilder: (_, i) => _bubble(_messages[i]),
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
