// Website chat inbox for staff — mirrors the "Website chats" panel on the web Website Widget page
// (frontend/src/pages/wa-agent/widget/LiveChatPanel.tsx): Unread / Read / Closed tabs, plus live
// chat handling (accept, reply, end). Polls the same Laravel /widgets/live/* endpoints.
import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:unichat_mobile_app/features/modules/_shared.dart';

const _tabs = [('unread', 'Unread'), ('read', 'Read'), ('closed', 'Closed')];
const _poll = Duration(seconds: 3);
const _maxBytes = 2 * 1024 * 1024; // chat files are capped at 2 MB (also enforced server-side)
const _emojis = ['😀', '😁', '😂', '🤣', '😊', '😍', '😘', '😎', '🤔', '😢', '😭', '😡', '👍', '👎', '👏', '🙏', '🙌', '💪', '🎉', '🔥', '❤️', '💯', '✅', '❌', '👋', '🤝', '😅', '😉', '🙂', '😇'];

class WidgetChatsPage extends StatefulWidget {
  const WidgetChatsPage({super.key});
  @override
  State<WidgetChatsPage> createState() => _WidgetChatsPageState();
}

class _WidgetChatsPageState extends State<WidgetChatsPage> with SingleTickerProviderStateMixin {
  late final TabController _tc = TabController(length: _tabs.length, vsync: this)..addListener(_onTab);
  List<Rec> _rows = [];
  Map<String, int> _counts = {'unread': 0, 'read': 0, 'closed': 0};
  bool _loading = true;
  Timer? _timer;
  final _seenWaiting = <int>{};
  bool _firstLoad = true;
  bool _muted = false;
  bool _forbidden = false;
  int _handling = 0;
  int _limit = 5;

  String get _tab => _tabs[_tc.index].$1;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(_poll, (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _tc.dispose();
    super.dispose();
  }

  void _onTab() {
    if (_tc.indexIsChanging) return;
    setState(() { _loading = true; _rows = []; });
    _load();
  }

  Future<void> _load({bool silent = false}) async {
    final tab = _tab;
    try {
      final me = await Api.raw.get('/widgets/live/me');
      final m = (me.data as Map).cast<String, dynamic>();
      _muted = m['muted'] == true;
      _handling = (m['handling'] as num?)?.toInt() ?? 0;
      _limit = (m['limit'] as num?)?.toInt() ?? 5;
      final res = await Api.raw.get('/widgets/live/inbox', queryParameters: {'tab': tab});
      final body = (res.data as Map).cast<String, dynamic>();
      final list = (body['data'] as List? ?? []).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
      final c = (body['counts'] as Map?)?.cast<String, dynamic>() ?? {};
      if (!mounted || tab != _tab) return;

      // Snackbar once per newly waiting live request (not for ones already waiting when the page opened).
      if (tab == 'unread') {
        for (final r in list.where((r) => r['live_status'] == 'waiting')) {
          final id = (r['id'] as num).toInt();
          if (_seenWaiting.add(id) && !_firstLoad && !_muted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('💬 ${r['visitor_name'] ?? 'Visitor'} is waiting for assistance'),
            ));
          }
        }
        _firstLoad = false;
      }
      setState(() {
        _rows = list;
        _counts = {for (final t in _tabs) t.$1: (c[t.$1] as num?)?.toInt() ?? 0};
        _loading = false;
      });
    } on DioException catch (e) {
      if (mounted) setState(() { _loading = false; if (e.response?.statusCode == 403) _forbidden = true; });
    } catch (_) {
      if (mounted && !silent) setState(() => _loading = false);
    }
  }

  Future<void> _toggleMute() async {
    try {
      final r = await Api.raw.put('/widgets/live/me', data: {'muted': !_muted});
      if (mounted) setState(() => _muted = (r.data as Map)['muted'] == true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
    }
  }

  Future<void> _accept(Rec r) async {
    try {
      await Api.raw.post('/widgets/live/${r['id']}/accept');
      await _open(r);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
      _load();
    }
  }

  Future<void> _open(Rec r) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => _WidgetChatDetailPage(id: (r['id'] as num).toInt(), title: (r['visitor_name'] ?? 'Visitor').toString())));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Website Chats  $_handling/$_limit'),
        actions: [
          IconButton(
            tooltip: _muted ? 'Alerts muted — tap to turn on' : 'Mute new-chat alerts',
            icon: Icon(_muted ? Icons.notifications_off_rounded : Icons.notifications_active_rounded),
            onPressed: _toggleMute,
          ),
        ],
        bottom: TabBar(controller: _tc, tabs: [
          for (final t in _tabs) Tab(text: _counts[t.$1]! > 0 ? '${t.$2} (${_counts[t.$1]})' : t.$2),
        ]),
      ),
      body: _forbidden
          ? const Center(child: Padding(padding: EdgeInsets.all(32), child: Text("You don't have access to website live chats. Ask an admin for the “Handle Website Live Chats” permission.", textAlign: TextAlign.center)))
          : _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _rows.isEmpty
                  ? ListView(children: [Padding(padding: const EdgeInsets.all(48), child: Center(child: Text('No $_tab chats.')))])
                  : ListView.separated(
                      itemCount: _rows.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) => _row(_rows[i]),
                    ),
            ),
    );
  }

  Widget _row(Rec r) {
    final live = r['live_status'] as String?;
    final canAccept = live == 'waiting' || live == 'missed';
    final unread = _tab == 'unread';
    final chip = switch (live) {
      'waiting' => ('Waiting', Colors.orange),
      'live' => ('Live', Colors.green),
      'missed' => (r['callback_confirmed_at'] != null ? 'Call back' : 'Missed', Colors.red),
      _ => null,
    };
    return ListTile(
      onTap: () => _open(r),
      title: Row(children: [
        Expanded(child: Text((r['visitor_name'] ?? 'Visitor').toString(),
            style: TextStyle(fontWeight: unread ? FontWeight.w700 : FontWeight.w500), overflow: TextOverflow.ellipsis)),
        if (chip != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: chip.$2.withValues(alpha: .12), borderRadius: BorderRadius.circular(99)),
            child: Text(chip.$1, style: TextStyle(fontSize: 11, color: chip.$2, fontWeight: FontWeight.w600)),
          ),
      ]),
      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${r['visitor_phone'] ?? 'No number'} · ${(r['widget'] as Map?)?['name'] ?? ''}', style: const TextStyle(fontSize: 12)),
        if (r['last_text'] != null) Text(r['last_text'].toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        if (canAccept)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: FilledButton(onPressed: () => _accept(r), child: Text(live == 'waiting' ? 'Accept chat' : 'Start chat')),
          ),
      ]),
      trailing: unread ? const Icon(Icons.circle, size: 10, color: Colors.blue) : null,
    );
  }
}

class _WidgetChatDetailPage extends StatefulWidget {
  const _WidgetChatDetailPage({required this.id, required this.title});
  final int id;
  final String title;
  @override
  State<_WidgetChatDetailPage> createState() => _WidgetChatDetailPageState();
}

class _WidgetChatDetailPageState extends State<_WidgetChatDetailPage> {
  final _msgs = <Rec>[];
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _player = AudioPlayer();
  Rec _convo = {};
  Rec? _replyTo;
  bool _emojiOpen = false;
  String? _playingUrl;
  int _lastId = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _fetch();
    _timer = Timer.periodic(_poll, (_) => _fetch());
    _player.onPlayerComplete.listen((_) { if (mounted) setState(() => _playingUrl = null); });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _input.dispose();
    _scroll.dispose();
    _player.dispose();
    super.dispose();
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _fetch() async {
    try {
      // Also marks the conversation read on the server.
      final res = await Api.raw.get('/widgets/live/${widget.id}', queryParameters: {'after': _lastId});
      final body = (res.data as Map).cast<String, dynamic>();
      final fresh = (body['messages'] as List? ?? []).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
      if (!mounted) return;
      setState(() {
        _convo = (body['conversation'] as Map?)?.cast<String, dynamic>() ?? _convo;
        if (fresh.isNotEmpty) {
          _lastId = (fresh.last['id'] as num).toInt();
          _msgs.addAll(fresh);
        }
      });
      if (fresh.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent + 80, duration: const Duration(milliseconds: 150), curve: Curves.easeOut);
        });
      }
    } catch (_) {}
  }

  Future<void> _post({String? text, String? path, String? name}) async {
    if (path != null && await File(path).length() > _maxBytes) {
      _snack('File is too large — the limit is 2 MB.');
      return;
    }
    try {
      final form = FormData.fromMap({
        if (text != null && text.isNotEmpty) 'text': text,
        if (_replyTo != null) 'reply_to_id': _replyTo!['id'],
        if (path != null) 'file': await MultipartFile.fromFile(path, filename: name ?? path.split('/').last),
      });
      await Api.raw.post('/widgets/live/${widget.id}/reply', data: form);
      setState(() { _replyTo = null; _emojiOpen = false; });
      _fetch();
    } catch (e) {
      if (text != null) _input.text = text;
      if (mounted) _snack(apiErrorMessage(e));
    }
  }

  Future<void> _send() async {
    final t = _input.text.trim();
    if (t.isEmpty) return;
    _input.clear();
    await _post(text: t);
  }

  Future<void> _attach() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Wrap(children: [
          ListTile(leading: const Icon(Icons.photo_camera_rounded), title: const Text('Camera'), onTap: () => Navigator.pop(context, 'camera')),
          ListTile(leading: const Icon(Icons.image_rounded), title: const Text('Photo'), onTap: () => Navigator.pop(context, 'gallery')),
          ListTile(leading: const Icon(Icons.attach_file_rounded), title: const Text('File (max 2 MB)'), onTap: () => Navigator.pop(context, 'file')),
        ]),
      ),
    );
    if (choice == null) return;
    if (choice == 'file') {
      final r = await FilePicker.platform.pickFiles();
      final f = r?.files.single;
      if (f?.path != null) await _post(path: f!.path, name: f.name);
    } else {
      final x = await ImagePicker().pickImage(
        source: choice == 'camera' ? ImageSource.camera : ImageSource.gallery,
        maxWidth: 1600, imageQuality: 80, // keeps photos comfortably under the 2 MB cap
      );
      if (x != null) await _post(path: x.path, name: x.name);
    }
  }

  Future<void> _record() async {
    final path = await showModalBottomSheet<String>(context: context, isDismissible: false, builder: (_) => const _VoiceSheet());
    if (path != null) await _post(path: path, name: 'voice.m4a');
  }

  Future<void> _end() async {
    try {
      await Api.raw.post('/widgets/live/${widget.id}/end');
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) _snack(apiErrorMessage(e));
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete conversation?'),
        content: const Text('This permanently deletes the chat and all its files.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Api.raw.delete('/widgets/live/${widget.id}');
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) _snack(apiErrorMessage(e));
    }
  }

  String _preview(Rec m) {
    final t = (m['text'] ?? '').toString();
    if (t.isNotEmpty) return t;
    return switch (m['type']) { 'image' => '📷 Photo', 'audio' => '🎤 Voice message', _ => '📎 ${m['file_name'] ?? 'File'}' };
  }

  Widget _content(Rec m, bool mine) {
    final url = m['url'] as String?;
    final color = mine ? Colors.white : null;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      if (m['reply_to'] is Map)
        Container(
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(border: Border(left: BorderSide(color: color ?? Colors.grey, width: 3)), color: Colors.black12),
          child: Text((m['reply_to'] as Map)['text'].toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: color)),
        ),
      if (m['type'] == 'image' && url != null)
        GestureDetector(
          onTap: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
          child: ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.network(url, width: 220, fit: BoxFit.cover)),
        ),
      if (m['type'] == 'audio' && url != null)
        InkWell(
          onTap: () async {
            if (_playingUrl == url) { await _player.stop(); setState(() => _playingUrl = null); return; }
            setState(() => _playingUrl = url);
            await _player.play(UrlSource(url));
          },
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(_playingUrl == url ? Icons.stop_circle_rounded : Icons.play_circle_fill_rounded, color: color),
            const SizedBox(width: 6),
            Text('Voice message', style: TextStyle(color: color)),
          ]),
        ),
      if (m['type'] == 'file' && url != null)
        InkWell(
          onTap: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
          child: Text('📎 ${m['file_name'] ?? 'File'}', style: TextStyle(color: color, decoration: TextDecoration.underline)),
        ),
      if ((m['text'] ?? '').toString().isNotEmpty) Text(m['text'].toString(), style: TextStyle(color: color)),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final live = _convo['live_status'] == 'live';
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.title, style: const TextStyle(fontSize: 16)),
          if (_convo['visitor_phone'] != null) Text(_convo['visitor_phone'].toString(), style: const TextStyle(fontSize: 12)),
        ]),
        actions: [
          if (live) TextButton(onPressed: _end, child: const Text('End chat')),
          PopupMenuButton<String>(
            onSelected: (v) { if (v == 'delete') _delete(); },
            itemBuilder: (_) => const [PopupMenuItem(value: 'delete', child: Text('Delete conversation'))],
          ),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.all(12),
            itemCount: _msgs.length,
            itemBuilder: (_, i) {
              final m = _msgs[i];
              final role = m['role'];
              if (role == 'system') {
                return Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Center(child: Text(m['text'].toString(), style: const TextStyle(fontSize: 12, color: Colors.grey), textAlign: TextAlign.center)));
              }
              final mine = role == 'staff';
              return Align(
                alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                child: GestureDetector(
                  onLongPress: live ? () => setState(() => _replyTo = m) : null, // long-press to quote-reply
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .78),
                    decoration: BoxDecoration(
                      color: mine ? Theme.of(context).colorScheme.primary : (role == 'agent' ? Colors.indigo.shade50 : Colors.grey.shade100),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: _content(m, mine),
                  ),
                ),
              );
            },
          ),
        ),
        if (live) ...[
          if (_replyTo != null)
            Container(
              color: Colors.grey.shade200,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(children: [
                Expanded(child: Text('↩ ${_preview(_replyTo!)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12))),
                InkWell(onTap: () => setState(() => _replyTo = null), child: const Icon(Icons.close, size: 18)),
              ]),
            ),
          if (_emojiOpen)
            SizedBox(
              height: 150,
              child: GridView.count(
                crossAxisCount: 8,
                children: [for (final e in _emojis) InkWell(onTap: () => _input.text += e, child: Center(child: Text(e, style: const TextStyle(fontSize: 24))))],
              ),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(children: [
                IconButton(onPressed: () => setState(() => _emojiOpen = !_emojiOpen), icon: const Icon(Icons.emoji_emotions_outlined)),
                IconButton(onPressed: _attach, icon: const Icon(Icons.attach_file_rounded)),
                Expanded(child: TextField(controller: _input, onSubmitted: (_) => _send(), decoration: const InputDecoration(hintText: 'Type a reply…', isDense: true, border: OutlineInputBorder()))),
                IconButton(onPressed: _record, icon: const Icon(Icons.mic_rounded)),
                IconButton.filled(onPressed: _send, icon: const Icon(Icons.send)),
              ]),
            ),
          ),
        ],
      ]),
    );
  }
}

/// Records a voice note (capped at 60 s so it stays under the 2 MB limit) and returns its file path.
class _VoiceSheet extends StatefulWidget {
  const _VoiceSheet();
  @override
  State<_VoiceSheet> createState() => _VoiceSheetState();
}

class _VoiceSheetState extends State<_VoiceSheet> {
  final _rec = AudioRecorder();
  Duration _elapsed = Duration.zero;
  Timer? _timer;
  String? _path;
  bool _denied = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    if (!await _rec.hasPermission()) {
      if (mounted) setState(() => _denied = true);
      return;
    }
    final dir = await getTemporaryDirectory();
    _path = '${dir.path}/chat_voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _rec.start(const RecordConfig(bitRate: 64000), path: _path!);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsed += const Duration(seconds: 1));
      if (_elapsed.inSeconds >= 60) _finish(send: true);
    });
  }

  Future<void> _finish({required bool send}) async {
    _timer?.cancel();
    final p = await _rec.stop();
    if (mounted) Navigator.pop(context, send ? (p ?? _path) : null);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _rec.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_denied) {
      return SafeArea(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('Microphone permission is required to record a voice message.'),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
      ])));
    }
    final t = '${_elapsed.inMinutes}:${(_elapsed.inSeconds % 60).toString().padLeft(2, '0')}';
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.mic_rounded, size: 48, color: Colors.red),
          Text(t, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            IconButton(onPressed: () => _finish(send: false), icon: const Icon(Icons.delete_outline_rounded, color: Colors.red), iconSize: 32),
            FloatingActionButton(onPressed: () => _finish(send: true), child: const Icon(Icons.send_rounded)),
          ]),
        ]),
      ),
    );
  }
}
