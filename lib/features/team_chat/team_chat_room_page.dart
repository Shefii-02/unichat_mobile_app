import 'dart:async';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:unichat_mobile_app/features/team_chat/delete_group_dialog.dart';
import 'package:flutter/material.dart';
import 'package:unichat_mobile_app/services/push_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:unichat_mobile_app/core/constants/app_colors.dart';
import 'package:unichat_mobile_app/core/network/api.dart';
import 'package:unichat_mobile_app/core/socket/socket_service.dart';
import 'package:unichat_mobile_app/core/theme/app_theme.dart';
import 'package:unichat_mobile_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:unichat_mobile_app/features/team_chat/team_chat_data.dart';
import 'package:unichat_mobile_app/features/team_chat/team_chats_page.dart';
import 'package:unichat_mobile_app/features/team_chat/chat_media_page.dart';
import 'package:unichat_mobile_app/features/team_chat/message_info_page.dart';
import 'package:unichat_mobile_app/features/team_chat/team_chat_actions.dart';
import 'package:unichat_mobile_app/features/team_chat/team_chat_style.dart';
import 'package:unichat_mobile_app/features/team_chat/team_api.dart';
import 'package:unichat_mobile_app/features/team_chat/team_media.dart';
import 'package:unichat_mobile_app/core/permissions/permission_guard.dart';
import 'package:url_launcher/url_launcher.dart';

const _quickReactions = ['👍', '❤️', '😂', '😮', '😢', '🙏'];

/// One conversation (direct or group): text, replies, @mentions, photos / videos / files,
/// voice notes, location + contact sharing, reactions, edit / delete / forward, read receipts
/// ("seen by" in groups), live typing — all realtime over the staff socket.
class TeamChatRoomPage extends ConsumerStatefulWidget {
  const TeamChatRoomPage({super.key, required this.chatId, this.jumpToMessageId});
  final int chatId;
  /// Open scrolled to this message (from search / mentions) instead of the newest.
  final int? jumpToMessageId;
  @override
  ConsumerState<TeamChatRoomPage> createState() => _TeamChatRoomPageState();
}

class _TeamChatRoomPageState extends ConsumerState<TeamChatRoomPage> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _focus = FocusNode();
  final _recorder = AudioRecorder();

  Map<String, dynamic>? _info;
  List<Map<String, dynamic>> _msgs = []; // ascending by id
  bool _loading = true, _loadingOlder = false, _noMore = false, _sending = false;
  String? _error;

  final _keys = <int, GlobalKey>{};
  List<Map<String, dynamic>> _pins = [];
  bool _showJump = false;
  int _newWhileAway = 0;
  int _tempSeq = 0;
  int? _highlight;
  // unread messages that @mention me, captured BEFORE the chat is marked read — the "@ N" chip walks through them
  List<int> _mentionQueue = [];
  // find-in-chat
  bool _finding = false;
  final _findCtrl = TextEditingController();
  Timer? _findDebounce;
  List<int> _hits = []; // message ids, oldest → newest
  int _hitIdx = -1;

  Map<String, dynamic>? _reply, _editing;
  final _mentionIds = <int, String>{}; // id -> name picked in the composer
  String? _mentionQuery;

  // recording
  bool _recording = false;
  int _recSeconds = 0;
  Timer? _recTimer;

  // realtime
  StreamSubscription? _evSub, _typSub, _connSub;
  Timer? _poll, _typingStop;
  final _typing = <int, ({String name, DateTime at})>{};
  DateTime _lastTypingEmit = DateTime.fromMillisecondsSinceEpoch(0);

  int get _me => ref.read(authProvider).value?.id ?? 0;
  bool get _group => _info?['type'] == 'group';
  Map<int, String> get _memberNames => {
        for (final m in (_info?['members'] as List? ?? const []).whereType<Map>()) (m['id'] as num).toInt(): '${m['name']}',
      };

  @override
  void initState() {
    super.initState();
    TeamChatsNotifier.openChatId = widget.chatId;
    _scroll.addListener(() {
      if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 200) _loadOlder();
      final away = _scroll.position.pixels > 360; // reverse list: 0 = newest at the bottom
      if (away != _showJump) setState(() { _showJump = away; if (!away) _newWhileAway = 0; });
    });
    _init();
    _evSub = SocketService().teamChatEvents.listen((e) {
      if ((e['chat_id'] as num?)?.toInt() != widget.chatId) return;
      final msg = e['message'];
      if (e['kind'] == 'pin') {
        _loadPins();
        _refreshLatest();
      } else if (e['kind'] == 'message' && msg is Map) {
        // Node already sent the personalised message — show it instantly, no round trip.
        final m = Map<String, dynamic>.from(msg);
        setState(() {
          // our own optimistic copy of this message is replaced by the real one
          if (m['mine'] == true) {
            _msgs.removeWhere((x) => x['pending'] == true &&
                (m['client_id'] != null ? x['client_id'] == m['client_id'] : x['body'] == m['body'] && x['type'] == m['type']));
          }
          _merge([m]);
          if (_showJump && m['mine'] != true) _newWhileAway++;
        });
        if (m['mine'] != true) _markRead();
      } else {
        _scheduleRefresh();
      }
    });
    _typSub = SocketService().teamTyping.listen((e) {
      if ((e['chat_id'] as num?)?.toInt() != widget.chatId) return;
      final uid = (e['user_id'] as num).toInt();
      setState(() {
        if (e['typing'] == false) {
          _typing.remove(uid);
        } else {
          _typing[uid] = (name: '${e['name'] ?? ''}', at: DateTime.now());
        }
      });
    });
    _connSub = SocketService().connectionState.listen((up) { if (up) _refreshLatest(); });
    _poll = Timer.periodic(const Duration(seconds: 6), (_) {
      _typing.removeWhere((_, v) => DateTime.now().difference(v.at).inSeconds > 5);
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    if (TeamChatsNotifier.openChatId == widget.chatId) TeamChatsNotifier.openChatId = null;
    _evDebounce?.cancel();
    _evSub?.cancel();
    _typSub?.cancel();
    _connSub?.cancel();
    _poll?.cancel();
    _typingStop?.cancel();
    _recTimer?.cancel();
    _findDebounce?.cancel();
    _findCtrl.dispose();
    _recorder.dispose();
    SocketService().emitTeamTyping(widget.chatId, false);
    _input.dispose();
    if (PushService.instance.openChatId == widget.chatId) PushService.instance.openChatId = null;
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    PushService.instance.openChatId = widget.chatId;
    try {
      _info = await TeamApi.one('/team-chat/chats/${widget.chatId}');
      try {
        final mine = await TeamApi.list('/team-chat/mentions');
        final q = [for (final x in mine) if ((x['chat_id'] as num?)?.toInt() == widget.chatId && x['unread'] == true) (x['id'] as num).toInt()]..sort();
        if (mounted) setState(() => _mentionQueue = q.where((id) => id != widget.jumpToMessageId).toList());
      } catch (_) {/* the chip just stays hidden */}
      if (widget.jumpToMessageId != null) {
        await _jumpTo(widget.jumpToMessageId!, initial: true);
      } else {
        await _refreshLatest(initial: true);
      }
      _loadPins();
    } catch (e) {
      if (mounted) setState(() { _error = apiErrorMessage(e); _loading = false; });
    }
  }

  void _merge(List<Map<String, dynamic>> incoming) {
    final byId = {for (final m in _msgs) (m['id'] as num).toInt(): m};
    for (final m in incoming) {
      byId[(m['id'] as num).toInt()] = m;
    }
    // Optimistic (not yet confirmed) messages have negative ids and always sort after real ones.
    num key(Map m) => (m['id'] as num) < 0 ? (1 << 50) + (-(m['id'] as num)) : (m['id'] as num);
    _msgs = byId.values.toList()..sort((a, b) => key(a).compareTo(key(b)));
  }

  bool _fetching = false, _fetchAgain = false;
  Timer? _evDebounce;

  /// Events arrive in bursts (read / delivered / reaction from every member). Coalesce them: one fetch at a time,
  /// and one more pass afterwards if something arrived meanwhile.
  void _scheduleRefresh() {
    _evDebounce?.cancel();
    _evDebounce = Timer(const Duration(milliseconds: 300), _refreshLatest);
  }

  Future<void> _refreshLatest({bool initial = false}) async {
    if (_fetching) { _fetchAgain = true; return; }
    _fetching = true;
    try {
      await _refreshLatestOnce(initial: initial);
    } finally {
      _fetching = false;
      if (_fetchAgain) { _fetchAgain = false; _refreshLatest(); }
    }
  }

  Future<void> _refreshLatestOnce({bool initial = false}) async {
    try {
      final rows = await TeamApi.list('/team-chat/chats/${widget.chatId}/messages', query: {'limit': initial ? 60 : 40});
      if (!mounted) return;
      final hadNewIncoming = rows.any((m) => m['mine'] != true && !_msgs.any((x) => x['id'] == m['id']));
      setState(() { _merge(rows); _loading = false; _error = null; if (initial && rows.length < 60) _noMore = true; });
      if (initial || hadNewIncoming) _markRead();
    } catch (e) {
      if (mounted && _msgs.isEmpty) setState(() { _error = apiErrorMessage(e); _loading = false; });
    }
  }

  /// Older page. Triggered by the "loading" row at the top of the list (so a short list that never
  /// scrolls still loads) and by scrolling near it. Stops for good when the server returns a short page.
  Future<void> _loadOlder() async {
    if (_loadingOlder || _noMore || _msgs.isEmpty) return;
    _loadingOlder = true;
    try {
      final rows = await TeamApi.list('/team-chat/chats/${widget.chatId}/messages',
          query: {'before_id': _msgs.first['id'], 'limit': 40});
      if (!mounted) return;
      setState(() { _merge(rows); if (rows.length < 40) _noMore = true; });
    } catch (_) {
      // leave _noMore false: the next scroll / rebuild retries
    } finally {
      _loadingOlder = false;
      if (mounted) setState(() {});
    }
  }

  /// Scrolls to [id], first loading the surrounding messages if it isn't in memory yet.
  Future<void> _jumpTo(int id, {bool initial = false}) async {
    try {
      if (!_msgs.any((m) => (m['id'] as num).toInt() == id)) {
        final rows = await TeamApi.list('/team-chat/chats/${widget.chatId}/messages', query: {'around_id': id});
        if (!mounted) return;
        setState(() { _merge(rows); _loading = false; _error = null; });
      } else if (initial) {
        setState(() => _loading = false);
      }
      _markRead();
      setState(() => _highlight = id);
      Future.delayed(const Duration(seconds: 2), () { if (mounted && _highlight == id) setState(() => _highlight = null); });
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToMessage(id));
    } catch (e) {
      if (mounted) setState(() { _error = _msgs.isEmpty ? apiErrorMessage(e) : null; _loading = false; });
    }
  }

  void _scrollToMessage(int id, {int attempt = 0}) {
    final ctx = _keys[id]?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx, alignment: 0.5, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      return;
    }
    if (attempt > 6 || !_scroll.hasClients) return;
    // Not built yet (far away in the lazy list): jump near it by index, let it build, then refine.
    final idx = _msgs.reversed.toList().indexWhere((m) => (m['id'] as num).toInt() == id);
    if (idx < 0) return;
    _scroll.jumpTo((idx * 84.0).clamp(0.0, _scroll.position.maxScrollExtent));
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToMessage(id, attempt: attempt + 1));
  }

  // ── find in chat ─────────────────────────────────────────────────────────

  void _onFind(String q) {
    _findDebounce?.cancel();
    _findDebounce = Timer(const Duration(milliseconds: 300), () async {
      final t = q.trim();
      if (t.isEmpty) { setState(() { _hits = []; _hitIdx = -1; }); return; }
      try {
        final rows = await TeamApi.list('/team-chat/chats/${widget.chatId}/messages', query: {'q': t, 'limit': 100});
        if (!mounted || _findCtrl.text.trim() != t) return;
        final ids = rows.map((m) => (m['id'] as num).toInt()).toList();
        setState(() { _hits = ids; _hitIdx = ids.isEmpty ? -1 : ids.length - 1; });
        if (ids.isNotEmpty) _jumpTo(ids.last);
      } catch (_) {}
    });
  }

  void _stepHit(int delta) {
    if (_hits.isEmpty) return;
    final n = (_hitIdx + delta).clamp(0, _hits.length - 1);
    setState(() => _hitIdx = n);
    _jumpTo(_hits[n]);
  }

  void _closeFind() => setState(() { _finding = false; _findCtrl.clear(); _hits = []; _hitIdx = -1; });

  Future<void> _loadPins() async {
    try {
      final rows = await Api.list('/team-chat/chats/${widget.chatId}/pins');
      if (mounted) setState(() => _pins = rows);
    } catch (_) {}
  }

  void _markRead() {
    _cmd('chat:read', {'chat_id': widget.chatId}, () => TeamApi.post('/team-chat/chats/${widget.chatId}/read'))
        .then((_) => ref.read(teamChatsProvider.notifier).refresh())
        .catchError((_) => <String, dynamic>{});
  }

  void _toast(String m) => ScaffoldMessenger.of(context)..hideCurrentSnackBar()..showSnackBar(SnackBar(content: Text(m)));

  String _newClientId() => '$_me-${DateTime.now().microsecondsSinceEpoch}';

  /// Socket-first command: Node saves + fans out + acks. If the socket is down / silent we use the REST
  /// endpoint (same rules server-side). Throws with the server's message when the command is rejected.
  Future<Map<String, dynamic>> _cmd(String event, Map<String, dynamic> data, Future<void> Function() rest) async {
    final res = await SocketService().call(event, data);
    if (res == null) {
      await rest();
      return const {'ok': true, 'rest': true};
    }
    if (res['ok'] != true) throw Exception('${res['error'] ?? 'Something went wrong.'}');
    return res;
  }

  // ── sending ──────────────────────────────────────────────────────────────

  List<int> _activeMentions(String text) {
    // every member written as "@Name" (typed by hand or picked) — followed by anything that is not part of a word
    final ids = <int>{
      for (final e in {..._memberNames, ..._mentionIds}.entries)
        if (e.key != _me && RegExp('(^|\\s)@${RegExp.escape(e.value)}(?![\\p{L}\\p{N}])', caseSensitive: false, unicode: true).hasMatch(text)) e.key,
    };
    // "@all" mentions every other member of the group (the server keeps only real members)
    if (_group && RegExp(r'(^|\s)@all(?![A-Za-z0-9])', caseSensitive: false).hasMatch(text)) {
      ids.addAll(_memberNames.keys.where((k) => k != _me));
    }
    return ids.toList();
  }

  Future<void> _sendText() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      if (_editing != null) {
        final id = _editing!['id'];
        await _cmd('chat:edit', {'message_id': id, 'body': text}, () => Api.patch('/team-chat/messages/$id', data: {'body': text}));
      } else {
        final payload = {
          'chat_id': widget.chatId,
          'client_id': _newClientId(),
          'body': text,
          if (_reply != null) 'reply_to_id': _reply!['id'],
          'mentions': _activeMentions(text),
        };
        // Show it immediately (clock icon) and swap in the server copy when the ack arrives.
        final tempId = -(++_tempSeq);
        setState(() => _merge([{
              'id': tempId, 'type': 'text', 'mine': true, 'pending': true, 'body': text, 'sender_id': _me, 'client_id': payload['client_id'],
              'created_at': DateTime.now().toUtc().toIso8601String(), 'reactions': const [], 'mentions': _activeMentions(text),
              if (_reply != null) 'reply_to': {'id': _reply!['id'], 'sender_name': _reply!['sender_name'], 'preview': _preview(_reply!), 'type': _reply!['type']},
            }]));
        _input.clear();
        _mentionIds.clear();
        _reply = null;
        _scrollToEnd();
        try {
          final res = await _cmd('chat:send', payload, () async {
            await TeamApi.post('/team-chat/chats/${widget.chatId}/messages', data: {...payload}..remove('chat_id'));
          });
          setState(() {
            _msgs.removeWhere((x) => x['id'] == tempId);
            if (res['message'] is Map) _merge([Map<String, dynamic>.from(res['message'] as Map)]);
          });
          if (res['rest'] == true) await _refreshLatest();
        } catch (e) {
          setState(() { final i = _msgs.indexWhere((x) => x['id'] == tempId); if (i >= 0) _msgs[i] = {..._msgs[i], 'pending': false, 'failed': true}; });
          _toast(apiErrorMessage(e));
        }
      }
      _input.clear();
      _mentionIds.clear();
      _reply = null;
      _editing = null;
      _stopTyping();
      if (_msgs.isEmpty || _editing != null) await _refreshLatest();
      _scrollToEnd();
    } catch (e) {
      _toast(apiErrorMessage(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _sendForm(Map<String, dynamic> fields, {String? filePath, String? fileName}) async {
    setState(() => _sending = true);
    try {
      final form = FormData.fromMap({
        'client_id': _newClientId(),
        ...fields,
        if (_reply != null) 'reply_to_id': _reply!['id'],
        if (filePath != null) 'file': await MultipartFile.fromFile(filePath, filename: fileName),
      });
      // Photos / videos / voice notes can be big: the default 30 s timeout is for small JSON calls, not uploads.
      await Api.raw.post('/team-chat/chats/${widget.chatId}/messages',
          data: form, options: Options(sendTimeout: const Duration(minutes: 5), receiveTimeout: const Duration(minutes: 2)));
      _reply = null;
      await _refreshLatest();
      _scrollToEnd();
    } catch (e) {
      _toast(apiErrorMessage(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _scrollToEnd() {
    if (_scroll.hasClients) _scroll.animateTo(0, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  void _onTyped(String v) {
    // @mention autocomplete: trailing "@word" at the cursor
    final m = RegExp(r'@([^\s@]*)$').firstMatch(v);
    setState(() => _mentionQuery = _group && m != null ? m.group(1)!.toLowerCase() : null);
    final now = DateTime.now();
    if (v.trim().isNotEmpty && now.difference(_lastTypingEmit).inSeconds >= 3) {
      _lastTypingEmit = now;
      SocketService().emitTeamTyping(widget.chatId, true);
    }
    _typingStop?.cancel();
    _typingStop = Timer(const Duration(seconds: 2), _stopTyping);
  }

  void _stopTyping() {
    _lastTypingEmit = DateTime.fromMillisecondsSinceEpoch(0);
    SocketService().emitTeamTyping(widget.chatId, false);
  }

  void _pickAll() {
    final t = _input.text;
    final i = t.lastIndexOf('@');
    final next = '${t.substring(0, i)}@all ';
    _input.value = TextEditingValue(text: next, selection: TextSelection.collapsed(offset: next.length));
    setState(() => _mentionQuery = null);
  }

  void _pickMention(int id, String name) {
    final t = _input.text;
    final i = t.lastIndexOf('@');
    final next = '${t.substring(0, i)}@$name ';
    _mentionIds[id] = name;
    _input.value = TextEditingValue(text: next, selection: TextSelection.collapsed(offset: next.length));
    setState(() => _mentionQuery = null);
  }

  // ── attachments ──────────────────────────────────────────────────────────

  Future<void> _attachSheet() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Wrap(children: [
          for (final o in const [
            ('camera', Icons.photo_camera_rounded, 'Camera', Color(0xFFEC4899)),
            ('gallery', Icons.photo_library_rounded, 'Photo', Color(0xFF7C3AED)),
            ('video', Icons.videocam_rounded, 'Video', Color(0xFFEF4444)),
            ('file', Icons.insert_drive_file_rounded, 'File', Color(0xFF0EA5E9)),
            ('location', Icons.location_on_rounded, 'Location', Color(0xFF16A34A)),
            ('contact', Icons.person_rounded, 'Contact', Color(0xFFF59E0B)),
          ])
            SizedBox(
              width: MediaQuery.of(context).size.width / 3,
              child: InkWell(
                onTap: () => Navigator.pop(context, o.$1),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Column(children: [
                    CircleAvatar(radius: 26, backgroundColor: o.$4.withOpacity(0.15), child: Icon(o.$2, color: o.$4)),
                    const SizedBox(height: 6),
                    Text(o.$3, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                  ]),
                ),
              ),
            ),
        ]),
      ),
    );
    if (choice == null) return;
    final picker = ImagePicker();
    switch (choice) {
      case 'camera':
        final x = await picker.pickImage(source: ImageSource.camera, imageQuality: 85);
        if (x != null) _sendForm({}, filePath: x.path, fileName: x.name);
      case 'gallery':
        final x = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
        if (x != null) _sendForm({}, filePath: x.path, fileName: x.name);
      case 'video':
        final x = await picker.pickVideo(source: ImageSource.gallery, maxDuration: const Duration(minutes: 5));
        if (x != null) _sendForm({}, filePath: x.path, fileName: x.name);
      case 'file':
        final r = await FilePicker.platform.pickFiles();
        final f = r?.files.single;
        if (f?.path != null) _sendForm({}, filePath: f!.path, fileName: f.name);
      case 'location':
        _shareLocation();
      case 'contact':
        _shareContact();
    }
  }

  /// Location / contact shares have no file, so they go over the socket like text.
  Future<void> _sendShare(Map<String, dynamic> fields) async {
    setState(() => _sending = true);
    try {
      final payload = {'chat_id': widget.chatId, 'client_id': _newClientId(), ...fields, if (_reply != null) 'reply_to_id': _reply!['id']};
      final res = await _cmd('chat:send', payload, () async {
        await Api.post('/team-chat/chats/${widget.chatId}/messages', data: FormData.fromMap({'client_id': payload['client_id'], ...fields, if (_reply != null) 'reply_to_id': _reply!['id']}));
      });
      if (res['message'] is Map) _merge([Map<String, dynamic>.from(res['message'] as Map)]);
      _reply = null;
      _scrollToEnd();
    } catch (e) {
      _toast(apiErrorMessage(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _shareLocation() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        _toast('Location permission is needed to share your location.');
        return;
      }
      final p = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Share your current location?'),
          content: Text('${p.latitude.toStringAsFixed(5)}, ${p.longitude.toStringAsFixed(5)}'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Send')),
          ],
        ),
      );
      if (ok == true) {
        _sendShare({'latitude': p.latitude, 'longitude': p.longitude, 'location_label': 'Current location'});
      }
    } catch (e) {
      _toast('Could not get your location.');
    }
  }

  Future<void> _shareContact() async {
    final name = TextEditingController(), phone = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Share a contact'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Name'), textCapitalization: TextCapitalization.words),
          TextField(controller: phone, decoration: const InputDecoration(labelText: 'Phone'), keyboardType: TextInputType.phone),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Send')),
        ],
      ),
    );
    if (ok == true && name.text.trim().isNotEmpty) {
      _sendShare({'contact_name': name.text.trim(), 'contact_phone': phone.text.trim()});
    }
  }

  // ── voice notes ──────────────────────────────────────────────────────────

  Future<void> _startRecording() async {
    try {
      if (!await _recorder.hasPermission()) {
        _toast('Microphone permission is needed for voice messages.');
        return;
      }
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: path);
      HapticFeedback.mediumImpact();
      setState(() { _recording = true; _recSeconds = 0; });
      _recTimer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() => _recSeconds++));
    } catch (_) {
      _toast('Could not start recording.');
    }
  }

  Future<void> _finishRecording({required bool send}) async {
    _recTimer?.cancel();
    final secs = _recSeconds;
    String? path;
    try { path = await _recorder.stop(); } catch (_) {}
    setState(() { _recording = false; _recSeconds = 0; });
    if (path == null) return;
    if (!send || secs < 1) {
      try { File(path).deleteSync(); } catch (_) {}
      return;
    }
    await _sendForm({'duration': secs}, filePath: path, fileName: 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a');
  }

  // ── message actions ──────────────────────────────────────────────────────

  /// Glass bottom sheet row.
  Widget _sheetTile(BuildContext ctx, IconData icon, String label, String value, {Color? color, String? subtitle}) => ListTile(
        leading: Icon(icon, color: color ?? Glass.accentDeep),
        title: Text(label, style: TextStyle(fontWeight: FontWeight.w700, color: color ?? Glass.text(ctx))),
        subtitle: subtitle == null ? null : Text(subtitle, style: TextStyle(color: Glass.muted(ctx), fontSize: 12)),
        onTap: () => Navigator.pop(ctx, value),
      );

  Future<String?> _glassSheet(List<Widget> Function(BuildContext) children) => showModalBottomSheet<String>(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (ctx) => Padding(
          padding: const EdgeInsets.all(12),
          child: GlassCard(
            opacity: 0.88,
            radius: 26,
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: SafeArea(top: false, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: children(ctx)))),
          ),
        ),
      );

  bool get _isModerator => PermissionGuard.can('staff.manage');

  Future<void> _actions(Map<String, dynamic> m) async {
    if (m['type'] == 'system') return;
    final mine = m['mine'] == true;
    final id = (m['id'] as num).toInt();

    // A message that never reached the server.
    if (m['failed'] == true) {
      final c = await _glassSheet((ctx) => [
            _sheetTile(ctx, Icons.refresh_rounded, 'Retry sending', 'retry'),
            _sheetTile(ctx, Icons.delete_outline_rounded, 'Discard', 'discard', color: Colors.red),
          ]);
      if (c == 'retry') {
        setState(() => _msgs.removeWhere((x) => x['id'] == id));
        _input.text = '${m['body'] ?? ''}';
        _sendText();
      } else if (c == 'discard') {
        setState(() => _msgs.removeWhere((x) => x['id'] == id));
      }
      return;
    }
    if (m['pending'] == true) return;

    // Deleted-for-everyone tombstone: members can only clear it for themselves; company admins can also
    // look at what it said and who removed it.
    if (m['deleted'] == true) {
      final c = await _glassSheet((ctx) => [
            if (_isModerator) _sheetTile(ctx, Icons.visibility_rounded, 'What was this message?', 'original', subtitle: 'Company admin view'),
            if (mine || _isModerator) _sheetTile(ctx, Icons.info_outline_rounded, 'Message info', 'info'),
            _sheetTile(ctx, Icons.delete_outline_rounded, 'Delete for me', 'delete_me', color: Colors.red),
          ]);
      try {
        if (c == 'original') await showOriginalMessage(context, id);
        if (c == 'info') Navigator.of(context).push(MaterialPageRoute(builder: (_) => MessageInfoPage(messageId: id, preview: 'This message was deleted')));
        if (c == 'delete_me') {
          await _cmd('chat:delete', {'message_id': id, 'scope': 'me'}, () => Api.delete('/team-chat/messages/$id?scope=me'));
          setState(() => _msgs.removeWhere((x) => x['id'] == id));
        }
      } catch (e) {
        _toast(apiErrorMessage(e));
      }
      return;
    }

    final admin = _info?['my_role'] == 'admin' && _group;
    final text = m['body'] as String?;
    final starred = m['starred'] == true, pinned = m['pinned'] == true;
    final canPin = !_group || admin || _info?['only_admins_edit'] != true;
    final choice = await _glassSheet((ctx) => [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              for (final e in _quickReactions)
                InkWell(
                  borderRadius: BorderRadius.circular(99),
                  onTap: () => Navigator.pop(ctx, 'react:$e'),
                  child: Padding(padding: const EdgeInsets.all(8), child: Text(e, style: const TextStyle(fontSize: 27))),
                ),
            ]),
          ),
          Divider(height: 1, color: Glass.border(ctx)),
          _sheetTile(ctx, Icons.reply_rounded, 'Reply', 'reply'),
          if (text != null && text.isNotEmpty) _sheetTile(ctx, Icons.copy_rounded, 'Copy', 'copy'),
          _sheetTile(ctx, Icons.forward_rounded, 'Forward', 'forward'),
          _sheetTile(ctx, starred ? Icons.star_rounded : Icons.star_border_rounded, starred ? 'Unstar' : 'Star', 'star', color: const Color(0xFFF59E0B)),
          if (canPin) _sheetTile(ctx, pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined, pinned ? 'Unpin' : 'Pin', 'pin'),
          if (mine && m['type'] == 'text') _sheetTile(ctx, Icons.edit_rounded, 'Edit', 'edit'),
          if (mine || _isModerator) _sheetTile(ctx, Icons.info_outline_rounded, 'Info', 'info', subtitle: 'Delivered & read details'),
          if (!mine) _sheetTile(ctx, Icons.flag_outlined, 'Report', 'report', color: Colors.orange.shade800),
          _sheetTile(ctx, Icons.delete_outline_rounded, 'Delete', 'delete', color: Colors.red),
        ]);
    if (choice == null) return;
    try {
      if (choice.startsWith('react:')) {
        final emoji = choice.substring(6);
        await _cmd('chat:react', {'message_id': id, 'emoji': emoji}, () => Api.post('/team-chat/messages/$id/react', data: {'emoji': emoji}));
        _refreshLatest();
        return;
      }
      switch (choice) {
        case 'reply':
          setState(() { _reply = m; _editing = null; });
          _focus.requestFocus();
        case 'copy':
          await Clipboard.setData(ClipboardData(text: text ?? ''));
          _toast('Copied');
        case 'edit':
          setState(() { _editing = m; _reply = null; _input.text = text ?? ''; });
          _focus.requestFocus();
        case 'forward':
          _forward(id);
        case 'star':
          await Api.post('/team-chat/messages/$id/star');
          _toast(starred ? 'Removed from starred' : 'Starred');
          _refreshLatest();
        case 'pin':
          await Api.post('/team-chat/messages/$id/pin');
          _loadPins();
          _refreshLatest();
        case 'info':
          if (mounted) Navigator.of(context).push(MaterialPageRoute(builder: (_) => MessageInfoPage(messageId: id, preview: _preview(m))));
        case 'report':
          await reportTeamMessage(context, id);
        case 'delete':
          final scope = await _glassSheet((ctx) => [
                Padding(padding: const EdgeInsets.fromLTRB(20, 14, 20, 6), child: Align(alignment: Alignment.centerLeft, child: Text('Delete message?', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Glass.text(ctx))))),
                if (mine || admin) _sheetTile(ctx, Icons.delete_sweep_rounded, 'Delete for everyone', 'everyone', color: Colors.red,
                    subtitle: 'Everyone sees "This message was deleted". Company admins can still review it.'),
                _sheetTile(ctx, Icons.person_off_outlined, 'Delete for me', 'me', color: Colors.red, subtitle: 'Only removed from your view.'),
              ]);
          if (scope == null) return;
          await _cmd('chat:delete', {'message_id': id, 'scope': scope}, () => Api.delete('/team-chat/messages/$id?scope=$scope'));
          if (scope == 'me') setState(() => _msgs.removeWhere((x) => x['id'] == id));
          _refreshLatest();
      }
    } catch (e) {
      _toast(apiErrorMessage(e));
    }
  }

  Future<void> _forward(int messageId) async {
    List<Map<String, dynamic>> chats;
    try {
      chats = (await Api.list('/team-chat/chats', query: {'per_page': 100})).where((c) => c['id'] != widget.chatId).toList();
    } catch (e) {
      _toast(apiErrorMessage(e));
      return;
    }
    final sel = <int>{};
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('Forward to'),
          content: SizedBox(
            width: double.maxFinite,
            child: chats.isEmpty
                ? const Text('No other chats yet.')
                : ListView(shrinkWrap: true, children: [
                    for (final c in chats)
                      CheckboxListTile(
                        value: sel.contains((c['id'] as num).toInt()),
                        onChanged: (v) => set(() => v == true ? sel.add((c['id'] as num).toInt()) : sel.remove((c['id'] as num).toInt())),
                        title: Text('${c['name']}', maxLines: 1, overflow: TextOverflow.ellipsis),
                        secondary: ChatAvatar(name: '${c['name']}', url: c['avatar'] as String?, group: c['type'] == 'group', radius: 18),
                      ),
                  ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: sel.isEmpty ? null : () => Navigator.pop(ctx, true), child: const Text('Forward')),
          ],
        ),
      ),
    );
    if (ok == true) {
      try {
        await _cmd('chat:forward', {'message_id': messageId, 'chat_ids': sel.toList()},
            () => Api.post('/team-chat/messages/$messageId/forward', data: {'chat_ids': sel.toList()}));
        ref.read(teamChatsProvider.notifier).refresh();
        _toast('Forwarded');
      } catch (e) {
        _toast(apiErrorMessage(e));
      }
    }
  }

  // ── UI ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = _group
        ? '${_info?['name'] ?? ''}'
        : '${(_info?['members'] as List? ?? const []).whereType<Map>().firstWhere((m) => m['id'] != _me, orElse: () => {'name': ''})['name']}';
    final typing = _typing.values.map((v) => v.name).where((n) => n.isNotEmpty).toList();
    final sub = typing.isNotEmpty
        ? (typing.length == 1 ? '${typing.first} is typing…' : '${typing.length} people typing…')
        : (_group ? '${(_info?['members'] as List? ?? const []).length} members' : null);

    final muted = _info?['muted'] == true;
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: _finding ? _findBar() : GlassAppBar(
        titleSpacing: 0,
        title: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => context.push('/team-chat/${widget.chatId}/info').then((_) => _init()),
          child: Row(children: [
            ChatAvatar(name: name, group: _group, radius: 19, url: _info?['avatar'] as String?),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800))),
                  if (muted) Padding(padding: const EdgeInsets.only(left: 5), child: Icon(Icons.volume_off_rounded, size: 14, color: Glass.muted(context))),
                ]),
                if (sub != null) Text(sub, style: TextStyle(fontSize: 11.5, color: typing.isNotEmpty ? Glass.accent : Glass.muted(context), fontWeight: typing.isNotEmpty ? FontWeight.w700 : FontWeight.w400)),
              ]),
            ),
          ]),
        ),
        actions: [
          IconButton(icon: const Icon(Icons.search_rounded), onPressed: () => setState(() => _finding = true)),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (v) async {
              switch (v) {
                case 'info':
                  context.push('/team-chat/${widget.chatId}/info').then((_) => _init());
                case 'mute':
                  if (await toggleMuteChat(context, ref, chatId: widget.chatId, muted: muted)) _init();
                case 'starred':
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => StarredMessagesPage(chatId: widget.chatId)));
                case 'media':
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatMediaPage(chatId: widget.chatId, title: name)));
                case 'delete':
                  final res = await deleteChatFlow(context, chatId: widget.chatId, name: name, group: _group);
                  if (res == ChatForget.none || !context.mounted) break;
                  ref.read(teamChatsProvider.notifier).refresh();
                  if (res == ChatForget.cleared) { _init(); } else { context.pop(); }
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'info', child: Text(_group ? 'Group info' : 'Contact info')),
              const PopupMenuItem(value: 'media', child: Text('Media, links and docs')),
              const PopupMenuItem(value: 'starred', child: Text('Starred messages')),
              PopupMenuItem(value: 'mute', child: Text(muted ? 'Unmute notifications' : 'Mute notifications')),
              PopupMenuItem(value: 'delete', child: Text(_group ? 'Delete / clear group chat…' : 'Delete / clear chat…', style: const TextStyle(color: Colors.red))),
            ],
          ),
        ],
      ),
      body: GlassBackground(
        child: SafeArea(
          bottom: false,
          child: Column(children: [
            const SizedBox(height: kToolbarHeight), // clears the translucent app bar
            if (_pins.isNotEmpty && !_finding) _pinBanner(),
            Expanded(
              child: Stack(children: [
                _body(theme),
                // "@ 2 mentions": jumps to the next unread message that mentions me
                if (_mentionQueue.isNotEmpty)
                  Positioned(
                    right: 14,
                    bottom: 64,
                    child: ActionChip(
                      backgroundColor: Glass.accentDeep,
                      side: BorderSide.none,
                      avatar: const Icon(Icons.alternate_email_rounded, size: 16, color: Colors.white),
                      label: Text('${_mentionQueue.length} mention${_mentionQueue.length > 1 ? 's' : ''}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                      onPressed: () {
                        final next = _mentionQueue.first;
                        setState(() => _mentionQueue = _mentionQueue.sublist(1));
                        _jumpTo(next);
                      },
                    ),
                  ),
                // Jump-to-latest button (shows when scrolled up; counts new messages that arrived meanwhile).
                Positioned(
                  right: 14,
                  bottom: 12,
                  child: AnimatedScale(
                    scale: _showJump ? 1 : 0,
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutBack,
                    child: Badge(
                      isLabelVisible: _newWhileAway > 0,
                      label: Text('$_newWhileAway'),
                      child: FloatingActionButton.small(
                        heroTag: null,
                        backgroundColor: Glass.panel(context, a: 0.9),
                        foregroundColor: Glass.accentDeep,
                        elevation: 3,
                        onPressed: _scrollToEnd,
                        child: const Icon(Icons.keyboard_arrow_down_rounded, size: 26),
                      ),
                    ),
                  ),
                ),
              ]),
            ),
            if (_mentionQuery != null) _mentionList(),
            if (_reply != null || _editing != null) _contextBar(),
            _composer(theme),
          ]),
        ),
      ),
    );
  }

  /// Pinned messages strip under the app bar. Tap to jump to the message (rotates through pins).
  int _pinIdx = 0;
  Widget _pinBanner() {
    final p = _pins[_pinIdx % _pins.length];
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
      child: GlassCard(
        radius: 16,
        padding: EdgeInsets.zero,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            _jumpTo((p['id'] as num).toInt());
            if (_pins.length > 1) setState(() => _pinIdx++);
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
            child: Row(children: [
              Container(width: 3, height: 30, decoration: BoxDecoration(color: Glass.accent, borderRadius: BorderRadius.circular(3))),
              const SizedBox(width: 10),
              const Icon(Icons.push_pin_rounded, size: 16, color: Glass.accentDeep),
              const SizedBox(width: 8),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_pins.length > 1 ? 'Pinned message ${(_pinIdx % _pins.length) + 1} of ${_pins.length}' : 'Pinned message',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Glass.accentDeep)),
                  Text(_preview(p), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: Glass.text(context))),
                ]),
              ),
              Text(teamTime(p['created_at']), style: TextStyle(fontSize: 11, color: Glass.muted(context))),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.close_rounded, size: 18, color: Glass.muted(context)),
                onPressed: () async {
                  try {
                    await Api.post('/team-chat/messages/${p['id']}/pin');
                    _loadPins();
                  } catch (e) { _toast(apiErrorMessage(e)); }
                },
              ),
            ]),
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _findBar() => GlassAppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: _closeFind),
        title: TextField(
          controller: _findCtrl,
          autofocus: true,
          onChanged: _onFind,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(hintText: 'Find in chat', border: InputBorder.none),
        ),
        actions: [
          if (_findCtrl.text.trim().isNotEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Text(_hits.isEmpty ? 'No results' : '${_hitIdx + 1} of ${_hits.length}', style: TextStyle(fontSize: 12.5, color: context.mutedColor)),
              ),
            ),
          IconButton(icon: const Icon(Icons.keyboard_arrow_up_rounded), onPressed: _hitIdx > 0 ? () => _stepHit(-1) : null),
          IconButton(icon: const Icon(Icons.keyboard_arrow_down_rounded), onPressed: _hitIdx >= 0 && _hitIdx < _hits.length - 1 ? () => _stepHit(1) : null),
        ],
      );

  Widget _body(ThemeData theme) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null && _msgs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.cloud_off_rounded, size: 48, color: Glass.muted(context)),
            const SizedBox(height: 10),
            Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: Glass.muted(context))),
            const SizedBox(height: 12),
            FilledButton.icon(onPressed: () { setState(() { _loading = true; _error = null; }); _init(); }, icon: const Icon(Icons.refresh_rounded), label: const Text('Try again')),
          ]),
        ),
      );
    }
    if (_msgs.isEmpty) {
      return Center(child: Text('No messages yet — say hello 👋', style: TextStyle(color: context.mutedColor)));
    }
    final rev = _msgs.reversed.toList();
    return ListView.builder(
      controller: _scroll,
      reverse: true,
      physics: teamScrollPhysics,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      itemCount: rev.length + (_noMore ? 0 : 1),
      itemBuilder: (_, i) {
        if (i == rev.length) {
          // The top-of-list loader asks for the next page the moment it is built.
          WidgetsBinding.instance.addPostFrameCallback((_) => _loadOlder());
          return const Padding(padding: EdgeInsets.all(12), child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))));
        }
        final m = rev[i];
        final older = i + 1 < rev.length ? rev[i + 1] : null;
        final showDay = older == null || teamDay(older['created_at']) != teamDay(m['created_at']);
        return Column(children: [
          if (showDay)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(color: context.lineColor.withOpacity(0.5), borderRadius: BorderRadius.circular(99)),
                child: Text(teamDay(m['created_at']), style: TextStyle(fontSize: 11.5, color: context.mutedColor, fontWeight: FontWeight.w600)),
              ),
            ),
          _MessageBubble(
            key: _keys.putIfAbsent((m['id'] as num).toInt(), () => GlobalKey()),
            highlight: _highlight == (m['id'] as num).toInt(),
            media: _mediaItems,
            m: m,
            group: _group,
            names: _memberNames,
            meId: _me,
            // group: show the sender's name when the previous (older) message is from someone else
            showSender: _group && m['mine'] != true && (older == null || older['sender_id'] != m['sender_id'] || showDay),
            onLongPress: () => _actions(m),
            onJump: (id) => _jumpTo(id),
            onReact: (e) => _cmd('chat:react', {'message_id': m['id'], 'emoji': e}, () => Api.post('/team-chat/messages/${m['id']}/react', data: {'emoji': e}))
                .then((_) => _refreshLatest())
                .catchError((_) => <String, dynamic>{}),
            onJumpReply: null,
          ),
        ]);
      },
    );
  }

  /// Every photo / video in the loaded history, oldest first — the swipe gallery's pages.
  List<MediaItem> get _mediaItems => [
        for (final x in _msgs)
          if ((x['type'] == 'image' || x['type'] == 'video') && x['deleted'] != true && x['attachment_url'] != null)
            MediaItem(
              url: '${x['attachment_url']}',
              isVideo: x['type'] == 'video',
              name: x['attachment_name'] as String?,
              sender: x['mine'] == true ? 'You' : x['sender_name'] as String?,
              time: '${teamDay(x['created_at'])} ${teamTime(x['created_at'])}',
            ),
      ];

  Widget _mentionList() {
    final me = _me;
    final list = _memberNames.entries
        .where((e) => e.key != me && (_mentionQuery!.isEmpty || e.value.toLowerCase().contains(_mentionQuery!)))
        .take(5)
        .toList();
    final showAll = _group && 'all'.startsWith(_mentionQuery!);
    if (list.isEmpty && !showAll) return const SizedBox.shrink();
    return Container(
      constraints: const BoxConstraints(maxHeight: 220),
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, border: Border(top: BorderSide(color: context.lineColor))),
      child: ListView(shrinkWrap: true, children: [
        if (showAll)
          ListTile(
            dense: true,
            leading: const CircleAvatar(radius: 14, child: Icon(Icons.alternate_email_rounded, size: 16)),
            title: const Text('@all'),
            subtitle: Text('Notify everyone in this group (${(_memberNames.length - 1).clamp(0, 9999)})'),
            onTap: _pickAll,
          ),
        for (final e in list)
          ListTile(dense: true, leading: ChatAvatar(name: e.value, radius: 14), title: Text('@${e.value}'), onTap: () => _pickMention(e.key, e.value)),
      ]),
    );
  }

  Widget _contextBar() {
    final m = _reply ?? _editing!;
    final editing = _editing != null;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
      decoration: BoxDecoration(color: Glass.panel(context, a: 0.8), border: const Border(left: BorderSide(color: Glass.accent, width: 4))),
      child: Row(children: [
        Icon(editing ? Icons.edit_rounded : Icons.reply_rounded, size: 18, color: AppColors.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(editing ? 'Editing message' : 'Replying to ${m['mine'] == true ? 'yourself' : (m['sender_name'] ?? '')}',
                style: TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w700)),
            Text(_preview(m), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: context.mutedColor, fontSize: 12.5)),
          ]),
        ),
        IconButton(
          icon: const Icon(Icons.close_rounded, size: 20),
          onPressed: () => setState(() { _reply = null; if (editing) { _editing = null; _input.clear(); } }),
        ),
      ]),
    );
  }

  Widget _composer(ThemeData theme) {
    final postingBlocked = _group && _info?['only_admins_post'] == true && _info?['my_role'] != 'admin';
    if (postingBlocked) {
      return SafeArea(
        top: false,
        child: Padding(padding: const EdgeInsets.all(14), child: Text('Only admins can send messages in this group', style: TextStyle(color: context.mutedColor))),
      );
    }
    if (_recording) {
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
          child: Row(children: [
            IconButton(icon: const Icon(Icons.delete_outline_rounded, color: Colors.red), onPressed: () => _finishRecording(send: false)),
            const Icon(Icons.fiber_manual_record_rounded, color: Colors.red, size: 14),
            const SizedBox(width: 8),
            Text('${(_recSeconds ~/ 60).toString().padLeft(2, '0')}:${(_recSeconds % 60).toString().padLeft(2, '0')}',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const Spacer(),
            Text('Recording…', style: TextStyle(color: context.mutedColor)),
            const SizedBox(width: 10),
            FloatingActionButton.small(
              heroTag: null,
              onPressed: () => _finishRecording(send: true),
              child: const Icon(Icons.send_rounded),
            ),
          ]),
        ),
      );
    }
    final hasText = _input.text.trim().isNotEmpty;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 6, 6, 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          IconButton(icon: const Icon(Icons.add_circle_outline_rounded, color: Glass.accentDeep, size: 28), onPressed: _sending ? null : _attachSheet),
          Expanded(
            child: TextField(
              controller: _input,
              focusNode: _focus,
              minLines: 1,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (v) { _onTyped(v); setState(() {}); },
              decoration: InputDecoration(
                hintText: _group ? 'Message the group — @ to mention' : 'Message',
                isDense: true,
                filled: true,
                fillColor: Glass.panel(context, a: 0.85),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide(color: Glass.border(context))),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide(color: Glass.border(context))),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: const BorderSide(color: Glass.accentSoft, width: 1.4)),
              ),
            ),
          ),
          const SizedBox(width: 6),
          hasText || _editing != null
              ? FloatingActionButton.small(heroTag: null, backgroundColor: Glass.accent, foregroundColor: Colors.white, elevation: 2, onPressed: _sending ? null : _sendText, child: _sending
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Icon(_editing != null ? Icons.check_rounded : Icons.send_rounded))
              : FloatingActionButton.small(heroTag: null, backgroundColor: Glass.accent, foregroundColor: Colors.white, elevation: 2, onPressed: _sending ? null : _startRecording, child: const Icon(Icons.mic_rounded)),
        ]),
      ),
    );
  }
}

String _preview(Map m) {
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

// ───────────────────────── message bubble ─────────────────────────

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    super.key, this.highlight = false, this.media = const [],
    required this.m, required this.group, required this.names, required this.meId,
    required this.showSender, required this.onLongPress, required this.onReact, this.onJumpReply, this.onJump,
  });
  final Map<String, dynamic> m;
  final bool group, showSender;
  final Map<int, String> names;
  final int meId;
  final VoidCallback onLongPress;
  final void Function(String emoji) onReact;
  final VoidCallback? onJumpReply;
  final void Function(int id)? onJump;
  final bool highlight;
  final List<MediaItem> media;

  @override
  Widget build(BuildContext context) {
    if (m['type'] == 'system') {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(color: Glass.panel(context, a: 0.6), borderRadius: BorderRadius.circular(12), border: Border.all(color: Glass.border(context))),
            child: Text('${m['body']}', textAlign: TextAlign.center, style: TextStyle(fontSize: 11.5, color: Glass.muted(context))),
          ),
        ),
      );
    }
    final mine = m['mine'] == true;
    final deleted = m['deleted'] == true;
    final bg = highlight ? Colors.amber.withOpacity(0.45) : (mine ? Glass.bubbleMine(context) : Glass.bubbleTheirs(context));
    final reactions = (m['reactions'] as List? ?? const []).whereType<Map>().toList();
    // ⏱ sending · ✓ sent · ✓✓ delivered (to everyone) · ✓✓ blue read (by everyone)
    final recipients = (m['recipients'] as num?)?.toInt() ?? 0;
    final deliveredN = (m['delivered_count'] as num?)?.toInt() ?? 0;
    final readN = (m['seen_by_count'] as num?)?.toInt() ?? 0;
    final pending = m['pending'] == true, failed = m['failed'] == true;
    final allRead = recipients > 0 && readN >= recipients;
    final allDelivered = recipients > 0 && deliveredN >= recipients;
    final mentionedMe = (m['mentions'] as List? ?? const []).contains(meId);

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: onLongPress,
        child: Container(
          margin: EdgeInsets.only(top: showSender ? 8 : 2, bottom: reactions.isEmpty ? 2 : 10, left: mine ? 46 : 0, right: mine ? 0 : 46),
          child: Stack(clipBehavior: Clip.none, children: [
            Container(
              padding: const EdgeInsets.fromLTRB(10, 7, 10, 5),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16), topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(mine ? 16 : 4), bottomRight: Radius.circular(mine ? 4 : 16)),
                border: Border.all(color: mentionedMe ? Glass.accent : Glass.border(context), width: mentionedMe ? 1.6 : 1),
                boxShadow: [BoxShadow(color: Glass.accent.withOpacity(0.10), blurRadius: 10, offset: const Offset(0, 3))],
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                if (showSender)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text('${m['sender_name'] ?? ''}',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: Colors.primaries[('${m['sender_name']}'.codeUnits.fold<int>(0, (a, b) => a + b)) % Colors.primaries.length].shade700)),
                  ),
                if (m['forwarded'] == true)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.forward_rounded, size: 13, color: context.mutedColor),
                      const SizedBox(width: 3),
                      Text('Forwarded', style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: context.mutedColor)),
                    ]),
                  ),
                if (m['reply_to'] is Map && !deleted) _replyQuote(context, m['reply_to'] as Map, mine),
                if (deleted)
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.block_rounded, size: 14, color: Glass.muted(context)),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        mine
                            ? (m['deleted_by_name'] != null && m['deleted_by_name'] != '' ? 'You deleted this message · by ${m['deleted_by_name']}' : 'You deleted this message')
                            : 'This message was deleted',
                        style: TextStyle(fontStyle: FontStyle.italic, color: Glass.muted(context), fontSize: 13),
                      ),
                    ),
                  ])
                else
                  _content(context),
                const SizedBox(height: 3),
                Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.end, children: [
                  if (m['pinned'] == true) Padding(padding: const EdgeInsets.only(right: 4), child: Icon(Icons.push_pin_rounded, size: 12, color: Glass.muted(context))),
                  if (m['starred'] == true) const Padding(padding: EdgeInsets.only(right: 4), child: Icon(Icons.star_rounded, size: 13, color: Color(0xFFF59E0B))),
                  if (m['edited'] == true) Text('edited  ', style: TextStyle(fontSize: 10.5, color: Glass.muted(context))),
                  Text(teamTime(m['created_at']), style: TextStyle(fontSize: 10.5, color: Glass.muted(context))),
                  if (mine && !deleted) ...[
                    const SizedBox(width: 4),
                    if (failed)
                      const Icon(Icons.error_outline_rounded, size: 15, color: Color(0xFFDC2626))
                    else if (pending)
                      Icon(Icons.schedule_rounded, size: 13, color: Glass.muted(context))
                    else
                      Icon(
                        allDelivered || allRead ? Icons.done_all_rounded : Icons.done_rounded,
                        size: 16,
                        color: allRead ? Glass.accent : Glass.muted(context),
                      ),
                  ],
                ]),
              ]),
            ),
            if (reactions.isNotEmpty)
              Positioned(
                bottom: -12,
                left: mine ? null : 8,
                right: mine ? 8 : null,
                child: Row(children: [
                  for (final r in reactions)
                    GestureDetector(
                      onTap: () => onReact('${r['emoji']}'),
                      onLongPress: () => showReactionDetails(context, (m['id'] as num).toInt()),
                      child: Container(
                        margin: const EdgeInsets.only(right: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: r['mine'] == true ? Glass.accent.withOpacity(0.22) : Glass.panel(context, a: 0.9),
                          borderRadius: BorderRadius.circular(99),
                          border: Border.all(color: r['mine'] == true ? Glass.accent : Glass.border(context)),
                        ),
                        child: Text('${r['emoji']} ${(r['count'] as num) > 1 ? r['count'] : ''}'.trim(), style: const TextStyle(fontSize: 12)),
                      ),
                    ),
                ]),
              ),
          ]),
        ),
      ),
    );
  }

  /// Quoted message inside the bubble (WhatsApp style): coloured bar, sender, preview, media thumbnail.
  /// Tap to jump to the original message.
  Widget _replyQuote(BuildContext context, Map r, bool mine) {
    final thumb = r['thumb'] as String?;
    final icon = switch ('${r['type']}') {
      'video' => Icons.videocam_rounded,
      'audio' => Icons.mic_rounded,
      'file' => Icons.insert_drive_file_rounded,
      'location' => Icons.location_on_rounded,
      'contact' => Icons.person_rounded,
      'image' => Icons.photo_rounded,
      _ => null,
    };
    return GestureDetector(
      onTap: onJump == null || r['id'] == null ? null : () => onJump!((r['id'] as num).toInt()),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
          color: (mine ? Glass.accent : Glass.accentDeep).withOpacity(0.10),
          borderRadius: BorderRadius.circular(10),
          border: const Border(left: BorderSide(color: Glass.accent, width: 4)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Flexible(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 5, 8, 5),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text('${r['sender_name'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11.5, color: Glass.accentDeep)),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  if (icon != null) Padding(padding: const EdgeInsets.only(right: 3), child: Icon(icon, size: 13, color: Glass.muted(context))),
                  Flexible(child: Text('${r['preview'] ?? ''}', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: Glass.muted(context)))),
                ]),
              ]),
            ),
          ),
          if (thumb != null)
            ClipRRect(
              borderRadius: const BorderRadius.horizontal(right: Radius.circular(10)),
              child: SizedBox(width: 44, height: 44, child: CachedChatImage(url: thumb, width: 44)),
            ),
        ]),
      ),
    );
  }

  Widget _content(BuildContext context) {
    switch (m['type']) {
      case 'image':
        return GestureDetector(
          onTap: () => _openGallery(context),
          child: ClipRRect(borderRadius: BorderRadius.circular(10), child: CachedChatImage(url: '${m['attachment_url']}', name: m['attachment_name'] as String?)),
        );
      case 'video':
        return _VideoTile(m: m, onOpen: () => _openGallery(context));
      case 'audio':
        return _VoiceNote(url: '${m['attachment_url']}', name: m['attachment_name'] as String?, seconds: (m['duration'] as num?)?.toInt() ?? 0);
      case 'file':
        return _FileTile(m: m);
      case 'location':
        final lat = m['latitude'], lng = m['longitude'];
        return InkWell(
          onTap: () => launchUrl(Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng'), mode: LaunchMode.externalApplication),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.green.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.location_on_rounded, color: Colors.green),
            ),
            const SizedBox(width: 10),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${m['location_label'] ?? 'Location'}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              Text('Tap to open in Maps', style: TextStyle(fontSize: 11, color: context.mutedColor)),
            ]),
          ]),
        );
      case 'contact':
        return InkWell(
          onTap: () => showModalBottomSheet(
            context: context,
            builder: (_) => SafeArea(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                ListTile(title: Text('${m['contact_name']}', style: const TextStyle(fontWeight: FontWeight.w800)), subtitle: Text('${m['contact_phone'] ?? ''}')),
                if ('${m['contact_phone'] ?? ''}'.isNotEmpty) ...[
                  ListTile(leading: const Icon(Icons.call_rounded), title: const Text('Call'), onTap: () { Navigator.pop(context); launchUrl(Uri.parse('tel:${m['contact_phone']}')); }),
                  ListTile(leading: const Icon(Icons.copy_rounded), title: const Text('Copy number'), onTap: () { Navigator.pop(context); Clipboard.setData(ClipboardData(text: '${m['contact_phone']}')); }),
                ],
              ]),
            ),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const CircleAvatar(backgroundColor: Color(0x33F59E0B), child: Icon(Icons.person_rounded, color: Color(0xFFF59E0B))),
            const SizedBox(width: 10),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${m['contact_name']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              if ('${m['contact_phone'] ?? ''}'.isNotEmpty) Text('${m['contact_phone']}', style: TextStyle(fontSize: 12, color: context.mutedColor)),
            ]),
          ]),
        );
    }
    return _richText(context, '${m['body'] ?? ''}');
  }

  void _openGallery(BuildContext context) {
    final url = '${m['attachment_url']}';
    final i = media.indexWhere((x) => x.url == url);
    final items = i >= 0 ? media : [MediaItem(url: url, isVideo: m['type'] == 'video', name: m['attachment_name'] as String?)];
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => MediaGalleryPage(items: items, initialIndex: i >= 0 ? i : 0)));
  }

  /// Body text with @mentions highlighted.
  Widget _richText(BuildContext context, String body) {
    final mentionNames = [
      for (final id in (m['mentions'] as List? ?? const [])) if (names[(id as num).toInt()] != null) names[id.toInt()]!,
    ];
    final style = const TextStyle(fontSize: 14.5, height: 1.3);
    if (RegExp(r'(^|\s)@all(?![A-Za-z0-9])', caseSensitive: false).hasMatch(body)) mentionNames.add('all');
    if (mentionNames.isEmpty) return Text(body, style: style);
    final re = RegExp('@(${mentionNames.map(RegExp.escape).join('|')})');
    final spans = <TextSpan>[];
    var last = 0;
    for (final mm in re.allMatches(body)) {
      if (mm.start > last) spans.add(TextSpan(text: body.substring(last, mm.start)));
      spans.add(TextSpan(text: mm.group(0), style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w800)));
      last = mm.end;
    }
    if (last < body.length) spans.add(TextSpan(text: body.substring(last)));
    return Text.rich(TextSpan(style: style.copyWith(color: Theme.of(context).colorScheme.onSurface), children: spans));
  }

}

/// Video bubble: poster tile that shows whether the file is already on the device; tap opens the gallery
/// player (which downloads it first if needed).
class _VideoTile extends StatelessWidget {
  const _VideoTile({required this.m, required this.onOpen});
  final Map<String, dynamic> m;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final size = (m['attachment_size'] as num?)?.toInt();
    return FutureBuilder<File?>(
      future: TeamMediaCache.cached('${m['attachment_url']}', name: m['attachment_name'] as String?),
      builder: (_, snap) {
        final local = snap.data != null;
        return GestureDetector(
          onTap: onOpen,
          child: Container(
            width: 220,
            height: 140,
            decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(10)),
            child: Stack(alignment: Alignment.center, children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: Colors.black54,
                child: Icon(local ? Icons.play_arrow_rounded : Icons.arrow_downward_rounded, color: Colors.white, size: 30),
              ),
              Positioned(
                bottom: 6,
                left: 8,
                child: Row(children: [
                  const Icon(Icons.videocam_rounded, color: Colors.white70, size: 14),
                  const SizedBox(width: 4),
                  Text(
                    [if (m['duration'] != null) '${(m['duration'] as num).toInt() ~/ 60}:${((m['duration'] as num).toInt() % 60).toString().padLeft(2, '0')}',
                      if (size != null && !local) size > 1048576 ? '${(size / 1048576).toStringAsFixed(1)} MB' : '${(size / 1024).toStringAsFixed(0)} KB'].join(' · '),
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                ]),
              ),
            ]),
          ),
        );
      },
    );
  }
}

/// Download state shared by the document and voice bubbles. The progress lives in [TeamMediaCache], so a bubble
/// that is rebuilt mid-download (new message, socket refresh, reopened chat) still shows the running download and
/// flips to "downloaded" the moment it finishes — no need to leave and reopen the chat.
mixin _DownloadState<T extends StatefulWidget> on State<T> {
  String get dlUrl;
  String? get dlName;

  bool local = false;
  double? dl; // null = idle, 0 = starting / size unknown, 0..1 = progress
  bool _starting = false;
  ValueNotifier<double>? _watched;

  void initDownload() {
    _sync();
    TeamMediaCache.done.addListener(_sync);
  }

  void disposeDownload() {
    TeamMediaCache.done.removeListener(_sync);
    _watched?.removeListener(_onProgress);
  }

  void _onProgress() { if (mounted) setState(() => dl = _watched?.value); }

  void _sync() {
    final n = TeamMediaCache.watch(dlUrl, name: dlName);
    if (!identical(n, _watched)) {
      _watched?.removeListener(_onProgress);
      _watched = n?..addListener(_onProgress);
    }
    if (mounted) setState(() => dl = n?.value ?? (_starting ? dl : null));
    TeamMediaCache.cached(dlUrl, name: dlName).then((f) { if (mounted) setState(() => local = f != null); });
  }

  /// Downloads (or reuses) the file, reporting progress. Returns null when the download failed.
  Future<File?> download() async {
    _starting = true;
    setState(() => dl = 0);
    try {
      final f = await TeamMediaCache.fetch(dlUrl, name: dlName);
      if (mounted) setState(() => local = true);
      return f;
    } catch (_) {
      return null;
    } finally {
      _starting = false;
      if (mounted) setState(() => dl = null);
    }
  }
}

/// Document bubble. Not on the device yet → download icon; tap shows live progress, then the file opens (PDFs in the
/// in-app viewer, other files through the system open-with sheet). Once downloaded it opens instantly, offline too.
class _FileTile extends StatefulWidget {
  const _FileTile({required this.m});
  final Map<String, dynamic> m;
  @override
  State<_FileTile> createState() => _FileTileState();
}

class _FileTileState extends State<_FileTile> with _DownloadState<_FileTile> {
  @override
  String get dlUrl => '${widget.m['attachment_url']}';
  @override
  String? get dlName => _name;
  String get _name => '${widget.m['attachment_name'] ?? 'File'}';
  bool get _pdf => '${widget.m['attachment_mime'] ?? ''}'.contains('pdf') || _name.toLowerCase().endsWith('.pdf');

  @override
  void initState() {
    super.initState();
    initDownload();
  }

  @override
  void dispose() {
    disposeDownload();
    super.dispose();
  }

  Future<void> _open() async {
    if (dl != null) return;
    if (!local && await download() == null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Download failed — tap to retry')));
      return;
    }
    if (mounted) await openTeamFile(context, url: dlUrl, name: _name, mime: widget.m['attachment_mime'] as String?);
  }

  String _size(int b) => b > 1048576 ? '${(b / 1048576).toStringAsFixed(1)} MB' : '${(b / 1024).toStringAsFixed(0)} KB';

  @override
  Widget build(BuildContext context) {
    final size = (widget.m['attachment_size'] as num?)?.toInt();
    final color = _pdf ? Colors.red : Colors.blue;
    final busy = dl != null;
    return InkWell(
      onTap: _open,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: color.withOpacity(0.14), borderRadius: BorderRadius.circular(10)),
          child: Icon(_pdf ? Icons.picture_as_pdf_rounded : Icons.insert_drive_file_rounded, color: color),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            Text(
              busy ? (dl! > 0 ? 'Downloading ${(dl! * 100).round()}%' : 'Downloading…') : [if (size != null) _size(size), if (!local) 'Tap to download'].join(' · '),
              style: TextStyle(fontSize: 11, color: context.mutedColor),
            ),
          ]),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 30,
          height: 30,
          child: busy
              ? Stack(alignment: Alignment.center, children: [
                  CircularProgressIndicator(value: dl! > 0 ? dl : null, strokeWidth: 2.6),
                  Icon(Icons.close_rounded, size: 12, color: context.mutedColor),
                ])
              : Icon(local ? Icons.check_circle_rounded : Icons.download_for_offline_rounded, size: 28, color: local ? Colors.green : context.mutedColor),
        ),
      ]),
    );
  }
}

/// Voice note player. Plays from the on-device copy when present; otherwise downloads it first (once) and
/// plays that, so a replay never touches the network.
class _VoiceNote extends StatefulWidget {
  const _VoiceNote({required this.url, required this.seconds, this.name});
  final String url;
  final String? name;
  final int seconds;
  @override
  State<_VoiceNote> createState() => _VoiceNoteState();
}

class _VoiceNoteState extends State<_VoiceNote> with _DownloadState<_VoiceNote> {
  @override
  String get dlUrl => widget.url;
  @override
  String? get dlName => widget.name ?? 'voice.m4a';

  final _p = AudioPlayer();
  bool _playing = false;
  Duration _pos = Duration.zero, _dur = Duration.zero;
  final _subs = <StreamSubscription>[];

  @override
  void initState() {
    super.initState();
    _dur = Duration(seconds: widget.seconds);
    initDownload();
    _subs.add(_p.onPlayerStateChanged.listen((s) { if (mounted) setState(() => _playing = s == PlayerState.playing); }));
    _subs.add(_p.onPositionChanged.listen((d) { if (mounted) setState(() => _pos = d); }));
    _subs.add(_p.onDurationChanged.listen((d) { if (mounted && d.inMilliseconds > 0) setState(() => _dur = d); }));
    _subs.add(_p.onPlayerComplete.listen((_) { if (mounted) setState(() { _playing = false; _pos = Duration.zero; }); }));
  }

  @override
  void dispose() {
    disposeDownload();
    for (final s in _subs) { s.cancel(); }
    _p.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_playing) { await _p.pause(); return; }
    if (_pos > Duration.zero) { await _p.resume(); return; }
    if (dl != null) return;
    try {
      // Not on the device yet → download first (the button shows the progress), then play straight away.
      final f = await TeamMediaCache.cached(widget.url, name: dlName) ?? await download();
      if (f == null) throw Exception('download failed');
      await _p.play(DeviceFileSource(f.path));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not play this voice message — tap to retry')));
    }
  }

  String _fmt(Duration d) => '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final progress = _dur.inMilliseconds == 0 ? 0.0 : (_pos.inMilliseconds / _dur.inMilliseconds).clamp(0.0, 1.0);
    return SizedBox(
      width: 220,
      child: Row(children: [
        InkWell(
          onTap: _toggle,
          child: CircleAvatar(
            radius: 19,
            backgroundColor: AppColors.primary,
            child: dl != null
                ? SizedBox(width: 22, height: 22, child: CircularProgressIndicator(value: dl! > 0 ? dl : null, strokeWidth: 2.4, color: Colors.white))
                : Icon(_playing ? Icons.pause_rounded : (local ? Icons.play_arrow_rounded : Icons.download_rounded), color: Colors.white),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SliderTheme(
              data: SliderTheme.of(context).copyWith(trackHeight: 3, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5), overlayShape: SliderComponentShape.noOverlay),
              child: Slider(value: progress, onChanged: (v) => _p.seek(Duration(milliseconds: (_dur.inMilliseconds * v).round()))),
            ),
            Text(dl != null ? (dl! > 0 ? 'Downloading ${(dl! * 100).round()}%' : 'Downloading…') : _playing || _pos > Duration.zero ? '${_fmt(_pos)} / ${_fmt(_dur)}' : _fmt(_dur), style: TextStyle(fontSize: 11, color: context.mutedColor)),
          ]),
        ),
        const Icon(Icons.mic_rounded, size: 16),
      ]),
    );
  }
}
