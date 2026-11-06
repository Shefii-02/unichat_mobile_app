// Website chat inbox for staff — mirrors the "Website chats" panel on the web Website Widget page
// (frontend/src/pages/wa-agent/widget/chats): Unread / Read / Closed tabs, plus live chat handling
// (accept, reply, end). Served by backend-node (/api/widget-chat/*) and kept current by socket pushes —
// polling only as a slow fallback while the socket is down. Photos / voice / files still upload via Laravel.
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
import 'package:unichat_mobile_app/core/network/dio_client.dart';
import 'package:unichat_mobile_app/core/socket/socket_service.dart';
import 'package:unichat_mobile_app/features/modules/_shared.dart';

const _tabs = [('unread', 'Unread'), ('read', 'Read'), ('closed', 'Closed')];
const _fallbackPoll = Duration(seconds: 30); // only while the realtime socket is down
const _node = '/api/widget-chat';
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
  StreamSubscription? _wsSub;
  StreamSubscription? _connSub;
  final _seenWaiting = <int>{};
  bool _firstLoad = true;
  bool _muted = false;
  bool _forbidden = false;
  int _handling = 0;
  int _limit = 5;
  String _q = '';
  String? _openKey;
  Timer? _debounce;
  Timer? _pushDebounce;

  String get _tab => _tabs[_tc.index].$1;

  @override
  void initState() {
    super.initState();
    _load();
    // Realtime: any change pushed by the server → refresh the list (debounced). Reconnect → resync.
    _wsSub = SocketService().widgetChatUpdates.listen((_) {
      _pushDebounce?.cancel();
      _pushDebounce = Timer(const Duration(milliseconds: 400), () => _load(silent: true));
    });
    _connSub = SocketService().connectionState.listen((up) { if (up) _load(silent: true); });
    _timer = Timer.periodic(_fallbackPoll, (_) { if (!SocketService().isConnected) _load(silent: true); });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _wsSub?.cancel();
    _connSub?.cancel();
    _pushDebounce?.cancel();
    _debounce?.cancel();
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
      final me = await DioClient.nodeDio.get('$_node/me');
      final m = (me.data as Map).cast<String, dynamic>();
      _muted = m['muted'] == true;
      _handling = (m['handling'] as num?)?.toInt() ?? 0;
      _limit = (m['limit'] as num?)?.toInt() ?? 5;
      final res = await DioClient.nodeDio.get('$_node/inbox', queryParameters: {'tab': tab, 'per_page': 100, if (_q.isNotEmpty) 'q': _q});
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

  // Same visitor (mobile number, else name) → one group; rows arrive latest-first so a group's first row is its latest chat.
  List<List<Rec>> get _groups {
    final m = <String, List<Rec>>{};
    for (final r in _rows) {
      final phone = (r['visitor_phone'] ?? '').toString().replaceAll(RegExp(r'\D+'), '');
      final name = (r['visitor_name'] ?? '').toString().trim().toLowerCase();
      final key = phone.isNotEmpty ? phone : (name.isNotEmpty ? 'n:$name' : 'id:${r['id']}');
      (m[key] ??= []).add(r);
    }
    return m.values.toList();
  }

  String _groupKey(Rec r) {
    final phone = (r['visitor_phone'] ?? '').toString().replaceAll(RegExp(r'\D+'), '');
    final name = (r['visitor_name'] ?? '').toString().trim().toLowerCase();
    return phone.isNotEmpty ? phone : (name.isNotEmpty ? 'n:$name' : 'id:${r['id']}');
  }

  Widget _pill(String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: c.withValues(alpha: .12), borderRadius: BorderRadius.circular(99)),
        child: Text(t, style: TextStyle(fontSize: 11, color: c, fontWeight: FontWeight.w600)),
      );

  // Live state wins; otherwise the case status (Pending / Unread / Attended / Solved), plus 🚩 when flagged.
  Widget? _badge(Rec r) {
    final live = r['live_status'];
    final cs = r['case_status'];
    Widget? w = switch (live) {
      'waiting' => _pill('Waiting', Colors.orange),
      'live' => _pill('Live', Colors.green),
      'missed' => _pill(r['callback_confirmed_at'] != null ? 'Call back' : 'Missed', Colors.red),
      _ => switch (cs) {
          'pending' => _pill('Pending', Colors.orange),
          'unread' => _pill('Unread', Colors.red),
          'attended' => _pill('Attended', Colors.blue),
          'closed' => _pill('Solved', Colors.grey),
          _ => null,
        },
    };
    if (r['flagged_at'] != null) w = Row(mainAxisSize: MainAxisSize.min, children: [if (w != null) w, const SizedBox(width: 4), const Text('🚩')]);
    return w;
  }

  Future<void> _toggleMute() async {
    try {
      final r = await DioClient.nodeDio.put('$_node/me', data: {'muted': !_muted});
      if (mounted) setState(() => _muted = (r.data as Map)['muted'] == true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
    }
  }

  Future<void> _accept(Rec r) async {
    try {
      await DioClient.nodeDio.post('$_node/${r['id']}/accept');
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
          : Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: TextField(
                  decoration: const InputDecoration(hintText: 'Search name / phone', prefixIcon: Icon(Icons.search), isDense: true, border: OutlineInputBorder()),
                  onChanged: (v) {
                    _debounce?.cancel();
                    _debounce = Timer(const Duration(milliseconds: 400), () { _q = v.trim(); _load(); });
                  },
                ),
              ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _load,
                  child: _rows.isEmpty
                      ? ListView(children: [Padding(padding: const EdgeInsets.all(48), child: Center(child: Text('No $_tab chats.')))])
                      : ListView(children: [for (final g in _groups) ..._group(g)]),
                ),
              ),
            ]),
    );
  }

  List<Widget> _group(List<Rec> list) {
    final r = list.first;
    final multi = list.length > 1;
    final key = _groupKey(r);
    final expanded = _openKey == key;
    return [
      _row(r, count: multi ? list.length : 0, expanded: expanded, onToggle: multi ? () => setState(() => _openKey = expanded ? null : key) : null),
      const Divider(height: 1),
      if (multi && expanded)
        for (final c in list) ...[
          ListTile(
            dense: true,
            contentPadding: const EdgeInsets.only(left: 28, right: 16),
            tileColor: Colors.grey.withValues(alpha: .06),
            onTap: () => _open(c),
            title: Row(children: [
              Expanded(child: Text(c['last_message_at'] != null ? DateTime.tryParse(c['last_message_at'].toString())?.toLocal().toString().split('.').first ?? '' : '', style: const TextStyle(fontSize: 12, color: Colors.grey))),
              if (_badge(c) != null) _badge(c)!,
            ]),
            subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (c['last_text'] != null) Text(c['last_text'].toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Colors.grey)),
              if (c['live_status'] == 'waiting' || c['live_status'] == 'missed')
                FilledButton(onPressed: () => _accept(c), child: Text(c['live_status'] == 'waiting' ? 'Accept chat' : 'Start chat')),
            ]),
          ),
          const Divider(height: 1),
        ],
    ];
  }

  Widget _row(Rec r, {int count = 0, bool expanded = false, VoidCallback? onToggle}) {
    final live = r['live_status'] as String?;
    final canAccept = live == 'waiting' || live == 'missed';
    final unread = _tab == 'unread';
    final badge = _badge(r);
    final by = r['staff_name'] != null && r['case_status'] == 'attended' ? ' · by ${r['staff_name']}' : '';
    return ListTile(
      onTap: () { _open(r); onToggle?.call(); },
      title: Row(children: [
        Expanded(child: Text((r['visitor_name'] ?? 'Visitor').toString(),
            style: TextStyle(fontWeight: unread ? FontWeight.w700 : FontWeight.w500), overflow: TextOverflow.ellipsis)),
        if (count > 0) Padding(padding: const EdgeInsets.only(right: 6), child: _pill('$count chats ${expanded ? '▴' : '▾'}', Colors.grey)),
        if (badge != null) badge,
      ]),
      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${r['visitor_phone'] ?? 'No number'} · ${(r['widget'] as Map?)?['name'] ?? ''}$by', style: const TextStyle(fontSize: 12)),
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
  Timer? _pushDebounce;
  StreamSubscription? _wsSub;
  StreamSubscription? _connSub;

  @override
  void initState() {
    super.initState();
    _fetch();
    // Realtime: pushes for THIS conversation → catch up since the last message id. No polling while the socket is up.
    _wsSub = SocketService().widgetChatUpdates.listen((e) {
      if ((e['conversation_id'] as num?)?.toInt() != widget.id) return;
      _pushDebounce?.cancel();
      _pushDebounce = Timer(const Duration(milliseconds: 150), _fetch);
    });
    _connSub = SocketService().connectionState.listen((up) { if (up) _fetch(); });
    _timer = Timer.periodic(_fallbackPoll ~/ 6, (_) { if (!SocketService().isConnected) _fetch(); });
    _player.onPlayerComplete.listen((_) { if (mounted) setState(() => _playingUrl = null); });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _wsSub?.cancel();
    _connSub?.cancel();
    _pushDebounce?.cancel();
    _input.dispose();
    _scroll.dispose();
    _player.dispose();
    super.dispose();
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _fetch() async {
    try {
      // Also marks the conversation read on the server.
      final res = await DioClient.nodeDio.get('$_node/${widget.id}', queryParameters: {'after': _lastId});
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
      if (path == null) {
        // Text goes straight to backend-node.
        await DioClient.nodeDio.post('$_node/${widget.id}/reply', data: {'text': text, if (_replyTo != null) 'reply_to_id': _replyTo!['id']});
      } else {
        // Files are stored by Laravel; the server then pushes the new message back over the socket.
        final form = FormData.fromMap({
          if (text != null && text.isNotEmpty) 'text': text,
          if (_replyTo != null) 'reply_to_id': _replyTo!['id'],
          'file': await MultipartFile.fromFile(path, filename: name ?? path.split('/').last),
        });
        await Api.raw.post('/widgets/live/${widget.id}/reply', data: form);
      }
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
      await DioClient.nodeDio.post('$_node/${widget.id}/end');
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) _snack(apiErrorMessage(e));
    }
  }

  Future<void> _flag() async {
    try {
      await Api.raw.post('/widgets/live/${widget.id}/flag');
      _snack('Marked as not satisfied — admin will review it.');
      _fetch();
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
    final live = _convo['live_status'] == 'live' && _convo['status'] != 'closed';
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.title, style: const TextStyle(fontSize: 16)),
          if (_convo['visitor_phone'] != null)
            Text('${_convo['visitor_phone']}${_convo['lead_id'] != null ? '  ✓ Saved in Contacts & Leads' : ''}', style: const TextStyle(fontSize: 12)),
        ]),
        actions: [
          if (live) TextButton(onPressed: _end, child: const Text('End chat')),
          PopupMenuButton<String>(
            onSelected: (v) { if (v == 'delete') _delete(); if (v == 'flag') _flag(); },
            itemBuilder: (_) => [
              if (_convo['flagged_at'] == null) const PopupMenuItem(value: 'flag', child: Text('🚩 Not satisfied')),
              const PopupMenuItem(value: 'delete', child: Text('Delete conversation')),
            ],
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
