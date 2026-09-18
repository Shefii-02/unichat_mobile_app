// The "📨 Campaign" tab of the WA Chat bulk sender — ports
// frontend/src/pages/wa-chat/pages/message-sender/index.tsx's composer onto the primary,
// server-tracked send path only: this creates a `MessageSenderJob` via `POST /message-sender` and
// lets the Laravel queue worker (ProcessMessageSenderJob) do the actual per-recipient sending —
// the web page's client-side fallback loop (used only when that POST itself fails) is not ported;
// campaign creation failing here just surfaces an error rather than silently switching to a
// slower, less-observable client-driven send.
//
// `message_payload` field names below (text/blocks/question/options/lat/lng/contactName/
// contactNumber/url, each with `recipients:[{name,phone}]`) mirror
// backend/app/Modules/WaChat/Jobs/ProcessMessageSenderJob.php's `match ($msgType)` exactly —
// change one side, change the other. Variable substitution ({{name}} etc.) and the anti-spam
// signature both happen server-side in that job; this composer only shows a client-side preview
// of the substitution (see campaign_models.dart), it never pre-substitutes what's actually sent.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mime/mime.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:share_plus/share_plus.dart';
import 'package:unichat_mobile_app/core/network/wa_chat_api_service.dart';
import 'package:unichat_mobile_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:unichat_mobile_app/features/message_sender/campaign_models.dart';
import 'package:unichat_mobile_app/features/modules/_shared.dart';
import 'package:unichat_mobile_app/features/modules/wa_chat_api.dart';
import 'package:unichat_mobile_app/features/modules/module_providers.dart';

enum _RTab { personal, group, csv, label, chat }
enum _MTab { text, media, template, poll, location, contact, audio }

class CampaignComposer extends ConsumerStatefulWidget {
  const CampaignComposer({super.key, required this.onSent});
  final VoidCallback onSent;
  @override
  ConsumerState<CampaignComposer> createState() => _CampaignComposerState();
}

class _CampaignComposerState extends ConsumerState<CampaignComposer> {
  // Mirrors chats_page.dart's _connectedStatuses — every status string a session reports when
  // it's actually usable for gateway calls, not just the literal 'ready'.
  static const _connectedStatuses = {'ready', 'connected', 'working', 'authenticated'};

  Rec? _session;

  // ── Recipients ────────────────────────────────────────────────────────────
  _RTab _rTab = _RTab.personal;
  List<CampaignRecipient> _recipients = [];

  final _personalSearchCtrl = TextEditingController();
  Timer? _personalDebounce;
  List<Rec> _personalResults = [];
  bool _personalLoading = false;
  final _manualNumberCtrl = TextEditingController();

  List<Rec>? _groups;
  bool _groupsLoading = false;
  final _groupSearchCtrl = TextEditingController();
  final Set<String> _selectedGroupIds = {};
  bool _resolvingGroupMembers = false;

  String? _csvFileName;
  List<CampaignRecipient> _csvValid = [];
  int _csvInvalidCount = 0;

  List<Rec>? _labels;
  bool _labelsLoading = false;
  final Set<dynamic> _selectedLabelIds = {};
  bool _resolvingLabelContacts = false;

  List<Rec>? _chats;
  bool _chatsLoading = false;
  final _chatSearchCtrl = TextEditingController();
  final Set<String> _selectedChatIds = {};

  // ── Message ──────────────────────────────────────────────────────────────
  _MTab _mTab = _MTab.text;
  final _textCtrl = TextEditingController();

  final List<CampaignMediaBlock> _mediaBlocks = [];

  List<Rec>? _templates;
  bool _templatesLoading = false;
  Rec? _selectedTemplate;

  final _pollQuestionCtrl = TextEditingController();
  final List<TextEditingController> _pollOptionCtrls = [TextEditingController(), TextEditingController()];
  bool _pollAllowMultiple = false;

  final _latCtrl = TextEditingController();
  final _lngCtrl = TextEditingController();
  final _locNameCtrl = TextEditingController();
  final _locAddrCtrl = TextEditingController();
  bool _locatingDevice = false;

  // The session's own WhatsApp address book (not CRM) — a "send a contact card" feature shares a
  // WhatsApp contact, which belongs to the session, not the company's CRM. Fetched once per
  // session (see _onSessionChanged) and filtered locally, same pattern as groups/chats: the
  // gateway's contacts endpoint has no server-side search.
  List<Rec>? _sessionContacts;
  bool _sessionContactsLoading = false;
  final _contactSearchCtrl = TextEditingController();
  List<Rec> _contactResults = [];
  Rec? _pickedContact;

  final _recorder = AudioRecorder();
  bool _recording = false;
  bool _uploadingAudio = false;
  String? _audioUrl;
  Duration _audioElapsed = Duration.zero;
  Timer? _audioTimer;

  // ── Sending options ──────────────────────────────────────────────────────
  final _campaignNameCtrl = TextEditingController();
  double _delaySeconds = 3;
  DateTime? _scheduledAt;
  bool _uniqueSignature = true;
  bool _sending = false;

  // Set once a reconnect actually succeeds — `authProvider`'s cached UserModel doesn't refresh
  // itself just because the company's wa_chat_token changed/got provisioned server-side, so this
  // overrides it locally (mirrors chats_page.dart / wa_sessions_page.dart's own override field).
  String? _apiKeyOverride;
  // Guards a single in-flight provisioning attempt so concurrent callers (Group tab, Chat tab,
  // Contact tab all missing the key at once) share one request instead of firing three.
  Future<String?>? _apiKeyProvisioning;

  String? get _apiKey => _apiKeyOverride ?? ref.read(authProvider).value?.waContactToken;

  /// Mints the company's FIRST wa_chat_token if none exists yet — safe to do silently since
  /// there's no existing key to revoke/kick another client with (see the same "missing key only"
  /// reasoning on chats_page.dart's auto-reconnect: an existing-but-rejected key must NOT be
  /// auto-reconnected here, since that revokes it and can kick a concurrently-open web tab).
  /// Returns the new key, or null if provisioning failed.
  Future<String?> _ensureApiKey() {
    if (_apiKey != null) return Future.value(_apiKey);
    return _apiKeyProvisioning ??= () async {
      try {
        final res = await WaChatApi.reconnectToken();
        final key = res['wa_chat_token'] as String?;
        if (key != null && key.isNotEmpty && mounted) setState(() => _apiKeyOverride = key);
        return key;
      } catch (e) {
        debugPrint('[Campaign] _ensureApiKey: provisioning failed — $e');
        return null;
      } finally {
        _apiKeyProvisioning = null;
      }
    }();
  }

  @override
  void dispose() {
    _personalDebounce?.cancel();
    _audioTimer?.cancel();
    _recorder.dispose();
    for (final c in [
      _personalSearchCtrl, _manualNumberCtrl, _groupSearchCtrl, _chatSearchCtrl, _textCtrl,
      _pollQuestionCtrl, _latCtrl, _lngCtrl, _locNameCtrl, _locAddrCtrl, _contactSearchCtrl,
      _campaignNameCtrl,
    ]) {
      c.dispose();
    }
    for (final c in _pollOptionCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  // ── Recipient plumbing ───────────────────────────────────────────────────

  void _addRecipients(Iterable<CampaignRecipient> additions) {
    setState(() => _recipients = mergeCampaignRecipients(_recipients, additions));
  }

  void _removeRecipient(CampaignRecipient r) {
    setState(() => _recipients = _recipients.where((x) => x.dedupeKey != r.dedupeKey).toList());
  }

  void _onPersonalSearchChanged(String v) {
    _personalDebounce?.cancel();
    final q = v.trim();
    if (q.isEmpty) {
      setState(() => _personalResults = []);
      return;
    }
    _personalDebounce = Timer(const Duration(milliseconds: 350), () async {
      setState(() => _personalLoading = true);
      try {
        final rows = await Api.list('/contacts', query: {'search': q, 'per_page': 20});
        if (mounted) setState(() { _personalResults = rows; _personalLoading = false; });
      } catch (_) {
        if (mounted) setState(() => _personalLoading = false);
      }
    });
  }

  void _addManualNumber() {
    final raw = _manualNumberCtrl.text.trim();
    final cleaned = raw.replaceAll(RegExp(r'[\s\-()]'), '');
    if (!campaignPhonePattern.hasMatch(cleaned)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid phone number (7–15 digits).')));
      return;
    }
    final phone = cleaned.startsWith('+') ? cleaned : '+$cleaned';
    _addRecipients([CampaignRecipient(id: 'manual-$phone', name: phone, phone: phone, type: 'personal', category: 'Manual')]);
    _manualNumberCtrl.clear();
  }

  Future<void> _loadGroups() async {
    final session = _session;
    if (session == null) return;
    final apiKey = await _ensureApiKey();
    if (apiKey == null) {
      debugPrint('[Campaign] _loadGroups: skipped — no wa_chat_token could be provisioned');
      return;
    }
    setState(() => _groupsLoading = true);
    try {
      final groups = await WaChatApiService.getGroups(str(session['session_name'], ''), apiKey);
      debugPrint('[Campaign] _loadGroups: got ${groups.length} group(s) for session ${session['session_name']}');
      if (mounted) setState(() { _groups = groups; _groupsLoading = false; });
    } catch (e) {
      debugPrint('[Campaign] _loadGroups: failed — $e');
      if (mounted) {
        setState(() => _groupsLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Couldn't load groups — ${apiErrorMessage(e)}")));
      }
    }
  }

  Future<void> _addGroupMembers() async {
    final session = _session;
    final apiKey = _apiKey;
    if (session == null || apiKey == null || _selectedGroupIds.isEmpty) return;
    setState(() => _resolvingGroupMembers = true);
    final toAdd = <CampaignRecipient>[];
    try {
      for (final gid in _selectedGroupIds) {
        final info = await WaChatApiService.getGroupInfo(str(session['session_name'], ''), apiKey, gid);
        final participants = (info['participants'] as List?)?.whereType<Map>().map((m) => m.cast<String, dynamic>()) ?? const <Rec>[];
        for (final p in participants) {
          final pid = str(p['id'], '');
          if (pid.isEmpty) continue;
          toAdd.add(CampaignRecipient(
            id: 'group-member-$pid',
            name: str(p['name'], str(p['number'], pid)),
            phone: pid,
            type: 'group',
            category: 'Group member',
          ));
        }
      }
      _addRecipients(toAdd);
      if (mounted) {
        setState(() { _resolvingGroupMembers = false; _selectedGroupIds.clear(); });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Added ${toAdd.length} member(s)')));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _resolvingGroupMembers = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
      }
    }
  }

  Future<void> _pickCsv() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['csv'], withData: true);
    final file = result?.files.single;
    if (file?.bytes == null) return;
    final text = utf8.decode(file!.bytes!, allowMalformed: true);
    final parsed = parseCampaignCsv(text);
    setState(() { _csvFileName = file.name; _csvValid = parsed.valid; _csvInvalidCount = parsed.invalidCount; });
  }

  static const _sampleCsv = 'phone,name\n+919876543210,John Doe\n+918765432100,Jane Smith\n';

  /// Copy-to-clipboard first (zero platform dependency, always works) — the OS share sheet
  /// (save / send / open in Files) is offered as a second, best-effort option since it can fail
  /// for reasons outside this app's control (no share targets installed, simulator limitations).
  Future<void> _shareSampleCsv() async {
    await Clipboard.setData(const ClipboardData(text: _sampleCsv));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sample CSV copied to clipboard')));
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/campaign_sample.csv');
      await file.writeAsString(_sampleCsv);
      if (mounted) await Share.shareXFiles([XFile(file.path)], text: 'Sample CSV for bulk campaign import');
    } catch (_) {
      // Already copied to clipboard above — sharing the file is a bonus, not required.
    }
  }

  Future<void> _loadLabels() async {
    setState(() => _labelsLoading = true);
    try {
      final labels = await Api.list('/labels');
      if (mounted) setState(() { _labels = labels; _labelsLoading = false; });
    } catch (e) {
      if (mounted) {
        setState(() => _labelsLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Couldn't load labels — ${apiErrorMessage(e)}")));
      }
    }
  }

  Future<void> _addLabelContacts() async {
    if (_selectedLabelIds.isEmpty) return;
    setState(() => _resolvingLabelContacts = true);
    try {
      final res = await Api.post('/contacts/by-labels', data: {'label_ids': _selectedLabelIds.toList()});
      final rows = (res['data'] as List?)?.whereType<Map>().map((m) => m.cast<String, dynamic>()).toList() ?? [];
      final toAdd = rows.map((c) => CampaignRecipient(
            id: 'label-contact-${c['id']}',
            name: str(c['name'], str(c['phone'], '')),
            phone: str(c['phone'], ''),
            type: 'label',
            category: 'Label',
          ));
      _addRecipients(toAdd);
      if (mounted) {
        setState(() { _resolvingLabelContacts = false; _selectedLabelIds.clear(); });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Added ${rows.length} contact(s)')));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _resolvingLabelContacts = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
      }
    }
  }

  Future<void> _loadChats() async {
    final session = _session;
    if (session == null) return;
    final apiKey = await _ensureApiKey();
    if (apiKey == null) {
      debugPrint('[Campaign] _loadChats: skipped — no wa_chat_token could be provisioned');
      return;
    }
    setState(() => _chatsLoading = true);
    try {
      final chats = await WaChatApiService.getChats(str(session['session_name'], ''), apiKey);
      debugPrint('[Campaign] _loadChats: got ${chats.length} chat(s) for session ${session['session_name']}');
      if (mounted) setState(() { _chats = chats; _chatsLoading = false; });
    } catch (e) {
      debugPrint('[Campaign] _loadChats: failed — $e');
      if (mounted) {
        setState(() => _chatsLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Couldn't load chats — ${apiErrorMessage(e)}")));
      }
    }
  }

  void _addSelectedChats() {
    final chats = _chats ?? [];
    final toAdd = chats.where((c) => _selectedChatIds.contains(str(c['id'], ''))).map((c) {
      final id = str(c['id'], '');
      final isGroup = c['isGroup'] == true;
      return CampaignRecipient(
        id: 'chat-$id',
        name: str(c['name'], id),
        phone: id,
        type: 'chat',
        category: isGroup ? 'Group chat' : 'Contact',
      );
    });
    _addRecipients(toAdd);
    setState(() => _selectedChatIds.clear());
  }

  // ── Media upload (shared by Multi Media blocks and the Audio tab) ──────────

  Future<String?> _uploadFile(String path, String filename) async {
    // Dio sets the request's own multipart/form-data + boundary header automatically for a
    // FormData body — MediaType below only tags this one part with its real content type, which
    // MultipartFile.fromFile can't infer on every platform on its own.
    final mimetype = lookupMimeType(path) ?? 'application/octet-stream';
    final res = await Api.raw.post(
      '/media-library/upload',
      data: FormData.fromMap({
        'file': await MultipartFile.fromFile(path, filename: filename, contentType: DioMediaType.parse(mimetype)),
      }),
    );
    final data = res.data;
    if (data is Map && data['url'] is String) return data['url'] as String;
    return null;
  }

  Future<void> _pickMediaBlockFile(CampaignMediaBlock block) async {
    final result = await FilePicker.platform.pickFiles(withData: false);
    final picked = result?.files.single;
    if (picked?.path == null) return;
    try {
      final url = await _uploadFile(picked!.path!, picked.name);
      if (url == null) throw Exception('Upload did not return a URL.');
      setState(() { block.mediaUrl = url; block.filename = picked.name; });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Couldn't upload — ${apiErrorMessage(e)}")));
    }
  }

  static const _libraryTypeByMime = {'image': 'image', 'video': 'video', 'audio': 'audio'};

  /// Lets a block reuse a file already sitting in the company's Media Library instead of
  /// uploading a fresh copy — mirrors the web's "🗂️ Browse Library" picker.
  Future<void> _browseLibrary(CampaignMediaBlock block) async {
    List<Rec> files;
    try {
      files = await Api.list('/media-library');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Couldn't load media library — ${apiErrorMessage(e)}")));
      return;
    }
    if (!mounted) return;
    final picked = await showModalBottomSheet<Rec>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        expand: false,
        builder: (ctx, scrollCtrl) => files.isEmpty
            ? Center(child: Text('Media Library is empty', style: TextStyle(color: ctx.mutedColor)))
            : ListView.separated(
                controller: scrollCtrl,
                padding: const EdgeInsets.all(16),
                itemCount: files.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (_, i) {
                  final f = files[i];
                  final mime = str(f['mime_type'], '');
                  final kind = _libraryTypeByMime[mime.split('/').first] ?? 'document';
                  final url = str(f['url'], '');
                  return ListTile(
                    dense: true,
                    leading: kind == 'image' && url.isNotEmpty
                        ? CircleAvatar(
                            radius: 20,
                            backgroundImage: NetworkImage(url),
                            onBackgroundImageError: (_, __) {},
                            child: const SizedBox.shrink(),
                          )
                        : CircleAvatar(
                            radius: 20,
                            child: Icon(switch (kind) {
                              'video' => Icons.videocam_rounded,
                              'audio' => Icons.audiotrack_rounded,
                              _ => Icons.insert_drive_file_rounded,
                            }),
                          ),
                    title: Text(str(f['display_name'] ?? f['original_name'], 'File'), maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(mime, style: const TextStyle(fontSize: 11)),
                    onTap: () => Navigator.pop(ctx, f),
                  );
                },
              ),
      ),
    );
    if (picked == null) return;
    final mime = str(picked['mime_type'], '');
    setState(() {
      block.type = _libraryTypeByMime[mime.split('/').first] ?? 'document';
      block.mediaUrl = str(picked['url'], '');
      block.filename = str(picked['display_name'] ?? picked['original_name'], '');
    });
  }

  // ── Template loading ─────────────────────────────────────────────────────

  Future<void> _loadTemplates() async {
    setState(() => _templatesLoading = true);
    try {
      final rows = await Api.list('/wa-chat-templates');
      final active = rows.where((t) => str(t['status'], '') != 'archived').toList();
      if (mounted) setState(() { _templates = active; _templatesLoading = false; });
    } catch (e) {
      if (mounted) {
        setState(() => _templatesLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Couldn't load templates — ${apiErrorMessage(e)}")));
      }
    }
  }

  static const _mediaHeaderTypes = {'image', 'video', 'audio', 'document'};

  /// Whether the selected template resolves to a media send (a header pointing at a file, or an
  /// explicit media_blocks list) rather than a plain text body — mirrors the web's promotion rule.
  bool get _templateIsMedia {
    final t = _selectedTemplate;
    if (t == null) return false;
    final blocks = t['media_blocks'];
    if (blocks is List && blocks.isNotEmpty) return true;
    final headerType = str(t['header_type'], '');
    return _mediaHeaderTypes.contains(headerType) && str(t['header_content'], '').isNotEmpty;
  }

  // ── Location ─────────────────────────────────────────────────────────────

  Future<void> _useCurrentLocation() async {
    setState(() => _locatingDevice = true);
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        throw Exception('Location permission is required.');
      }
      final pos = await Geolocator.getCurrentPosition();
      _latCtrl.text = pos.latitude.toString();
      _lngCtrl.text = pos.longitude.toString();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
    } finally {
      if (mounted) setState(() => _locatingDevice = false);
    }
  }

  // ── Session contact picker (for the Contact message tab) ────────────────

  Future<void> _loadSessionContacts() async {
    final session = _session;
    if (session == null) return;
    final apiKey = await _ensureApiKey();
    if (apiKey == null) {
      debugPrint('[Campaign] _loadSessionContacts: skipped — no wa_chat_token could be provisioned');
      return;
    }
    setState(() => _sessionContactsLoading = true);
    try {
      final contacts = await WaChatApiService.getSessionContacts(str(session['session_name'], ''), apiKey);
      debugPrint('[Campaign] _loadSessionContacts: got ${contacts.length} contact(s) for session ${session['session_name']}');
      if (mounted) {
        setState(() {
          _sessionContacts = contacts;
          _sessionContactsLoading = false;
          _contactResults = _filterSessionContacts(_contactSearchCtrl.text);
        });
      }
    } catch (e) {
      debugPrint('[Campaign] _loadSessionContacts: failed — $e');
      if (mounted) {
        setState(() => _sessionContactsLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Couldn't load contacts — ${apiErrorMessage(e)}")));
      }
    }
  }

  List<Rec> _filterSessionContacts(String query) {
    final all = _sessionContacts ?? [];
    final q = query.trim().toLowerCase();
    final matches = q.isEmpty
        ? all
        : all.where((c) => str(c['name'] ?? c['pushName'], '').toLowerCase().contains(q) || str(c['number'], '').contains(q)).toList();
    return matches.take(50).toList();
  }

  void _onContactSearchChanged(String v) => setState(() => _contactResults = _filterSessionContacts(v));

  // ── Audio recording ──────────────────────────────────────────────────────

  Future<void> _startRecording() async {
    if (!await _recorder.hasPermission()) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Microphone permission is required.')));
      return;
    }
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/campaign_audio_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(const RecordConfig(), path: path);
    setState(() { _recording = true; _audioElapsed = Duration.zero; _audioUrl = null; });
    _audioTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _audioElapsed += const Duration(seconds: 1));
    });
  }

  Future<void> _stopAndUploadRecording() async {
    _audioTimer?.cancel();
    final path = await _recorder.stop();
    setState(() { _recording = false; _uploadingAudio = true; });
    if (path == null) {
      setState(() => _uploadingAudio = false);
      return;
    }
    try {
      final url = await _uploadFile(path, 'voice-note.m4a');
      if (mounted) setState(() { _audioUrl = url; _uploadingAudio = false; });
    } catch (e) {
      if (mounted) {
        setState(() => _uploadingAudio = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Couldn't upload recording — ${apiErrorMessage(e)}")));
      }
    }
  }

  // ── Validation + payload ─────────────────────────────────────────────────

  bool get _canSend {
    if (_session == null || _recipients.isEmpty || _sending) return false;
    switch (_mTab) {
      case _MTab.text:
        return _textCtrl.text.trim().isNotEmpty;
      case _MTab.media:
        return _mediaBlocks.any((b) => (b.mediaUrl ?? '').isNotEmpty || (b.text ?? '').trim().isNotEmpty);
      case _MTab.template:
        return _selectedTemplate != null;
      case _MTab.poll:
        return _pollQuestionCtrl.text.trim().isNotEmpty &&
            _pollOptionCtrls.where((c) => c.text.trim().isNotEmpty).length >= 2;
      case _MTab.location:
        return double.tryParse(_latCtrl.text.trim()) != null && double.tryParse(_lngCtrl.text.trim()) != null;
      case _MTab.contact:
        return _pickedContact != null;
      case _MTab.audio:
        return _audioUrl != null && !_uploadingAudio;
    }
  }

  Map<String, dynamic>? _buildMessagePayload() {
    switch (_mTab) {
      case _MTab.text:
        final text = _textCtrl.text.trim();
        if (text.isEmpty) return null;
        return {'type': 'text', 'text': text};
      case _MTab.media:
        final blocks = _mediaBlocks.where((b) => (b.mediaUrl ?? '').isNotEmpty || (b.text ?? '').trim().isNotEmpty).toList();
        if (blocks.isEmpty) return null;
        return {'type': 'media', 'blocks': blocks.map((b) => b.toJson()).toList()};
      case _MTab.template:
        final t = _selectedTemplate;
        if (t == null) return null;
        if (_templateIsMedia) {
          final rawBlocks = t['media_blocks'];
          final blocks = (rawBlocks is List && rawBlocks.isNotEmpty)
              ? rawBlocks.whereType<Map>().map((m) => m.cast<String, dynamic>()).toList()
              : [
                  {
                    'type': str(t['header_type'], 'image'),
                    'mediaUrl': str(t['header_content'], ''),
                    if (str(t['body'], '').isNotEmpty) 'caption': str(t['body'], ''),
                  }
                ];
          return {'type': 'media', 'blocks': blocks};
        }
        return {'type': 'text', 'text': str(t['body'], '')};
      case _MTab.poll:
        final question = _pollQuestionCtrl.text.trim();
        final options = _pollOptionCtrls.map((c) => c.text.trim()).where((s) => s.isNotEmpty).toList();
        if (question.isEmpty || options.length < 2) return null;
        return {'type': 'poll', 'question': question, 'options': options, 'allowMultipleAnswers': _pollAllowMultiple};
      case _MTab.location:
        final lat = double.tryParse(_latCtrl.text.trim());
        final lng = double.tryParse(_lngCtrl.text.trim());
        if (lat == null || lng == null) return null;
        return {
          'type': 'location',
          'lat': lat,
          'lng': lng,
          if (_locNameCtrl.text.trim().isNotEmpty) 'name': _locNameCtrl.text.trim(),
          if (_locAddrCtrl.text.trim().isNotEmpty) 'address': _locAddrCtrl.text.trim(),
        };
      case _MTab.contact:
        final c = _pickedContact;
        if (c == null) return null;
        return {
          'type': 'contact',
          'contactName': str(c['name'] ?? c['pushName'], str(c['number'], '')),
          'contactNumber': str(c['number'], ''),
        };
      case _MTab.audio:
        if (_audioUrl == null) return null;
        return {'type': 'audio', 'url': _audioUrl};
    }
  }

  /// Preview text for the live "here's what recipient #1 sees" banner — text/template/media-first-
  /// text-block bodies only, same scope the web preview covers.
  String? get _previewBody {
    switch (_mTab) {
      case _MTab.text:
        return _textCtrl.text;
      case _MTab.template:
        return _templateIsMedia ? null : str(_selectedTemplate?['body'], '');
      case _MTab.media:
        return _mediaBlocks.isNotEmpty ? _mediaBlocks.first.text : null;
      default:
        return null;
    }
  }

  Future<void> _send() async {
    if (!_canSend) return;
    final payload = _buildMessagePayload();
    if (payload == null) return;
    setState(() => _sending = true);
    try {
      final data = {
        if (_campaignNameCtrl.text.trim().isNotEmpty) 'campaign_name': _campaignNameCtrl.text.trim(),
        'session_id': str(_session!['session_name'], ''),
        'type': _recipients.first.type,
        'total': _recipients.length,
        'delay_ms': (_delaySeconds * 1000).round(),
        'unique_signature': _uniqueSignature,
        if (_scheduledAt != null) 'scheduled_at': _scheduledAt!.toIso8601String(),
        'log': _recipients.map((r) => r.toLogEntry()).toList(),
        'message_payload': {
          ...payload,
          'recipients': _recipients.map((r) => {'name': r.name, 'phone': r.phone}).toList(),
        },
      };
      await Api.post('/message-sender', data: data);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_scheduledAt != null ? 'Campaign scheduled.' : 'Campaign launched.')),
      );
      setState(() {
        _recipients = [];
        _textCtrl.clear();
        _mediaBlocks.clear();
        _selectedTemplate = null;
        _pollQuestionCtrl.clear();
        for (final c in _pollOptionCtrls) {
          c.clear();
        }
        _latCtrl.clear();
        _lngCtrl.clear();
        _locNameCtrl.clear();
        _locAddrCtrl.clear();
        _pickedContact = null;
        _audioUrl = null;
        _campaignNameCtrl.clear();
        _scheduledAt = null;
        _sending = false;
      });
      widget.onSent();
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        Text('${_recipients.length} recipient(s) selected',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
        const SizedBox(height: 10),
        TextField(
          controller: _campaignNameCtrl,
          decoration: const InputDecoration(labelText: 'Campaign Name (optional)', hintText: 'e.g. Diwali Promo 2024'),
        ),
        const SizedBox(height: 18),
        _sectionTitle('WhatsApp Session'),
        _sessionPicker(),
        const SizedBox(height: 18),
        _sectionTitle('Recipients'),
        _recipientTabBar(),
        const SizedBox(height: 8),
        _recipientTabBody(),
        if (_recipients.isNotEmpty) ...[
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('Selected', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: context.mutedColor)),
            TextButton(onPressed: () => setState(() => _recipients = []), child: const Text('Clear all')),
          ]),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _recipients
                .map((r) => Chip(
                      label: Text(r.name, style: const TextStyle(fontSize: 12)),
                      onDeleted: () => _removeRecipient(r),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ))
                .toList(),
          ),
        ],
        const SizedBox(height: 22),
        _sectionTitle('Message'),
        _messageTabBar(),
        const SizedBox(height: 8),
        _messageTabBody(),
        if (_previewBody != null && _previewBody!.contains('{{') && _recipients.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 10),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: context.altSurface, borderRadius: BorderRadius.circular(8)),
            child: Text(
              'Preview for ${_recipients.first.name}: '
              '${personalizeCampaignPreview(_previewBody!, name: _recipients.first.name, phone: _recipients.first.phone)}',
              style: TextStyle(fontSize: 12, color: context.mutedColor),
            ),
          ),
        const SizedBox(height: 22),
        _sectionTitle('Sending Options'),
        _sendingOptions(),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _canSend ? _send : null,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          child: _sending
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text(_scheduledAt != null ? 'Schedule' : 'Send'),
        ),
      ],
    );
  }

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t.toUpperCase(),
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: context.mutedColor, letterSpacing: 0.4)),
      );

  // ── Recipient tab shell ──────────────────────────────────────────────────

  Widget _recipientTabBar() => Wrap(
        spacing: 6,
        children: [
          _chip('Personal', _rTab == _RTab.personal, () => setState(() => _rTab = _RTab.personal)),
          _chip('Group', _rTab == _RTab.group, () {
            setState(() => _rTab = _RTab.group);
            if (_groups == null) _loadGroups();
          }),
          _chip('Bulk CSV', _rTab == _RTab.csv, () => setState(() => _rTab = _RTab.csv)),
          _chip('Label', _rTab == _RTab.label, () {
            setState(() => _rTab = _RTab.label);
            if (_labels == null) _loadLabels();
          }),
          _chip('From Chat', _rTab == _RTab.chat, () {
            setState(() => _rTab = _RTab.chat);
            if (_chats == null) _loadChats();
          }),
        ],
      );

  Widget _chip(String label, bool selected, VoidCallback onTap) => ChoiceChip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        selected: selected,
        onSelected: (_) => onTap(),
      );

  /// A bordered, height-capped scroll box for a recipient-picker list (Personal/Group/Label/
  /// From Chat/Contact) — makes the multi-select area read as a distinct "pick from here" box
  /// on screen instead of an unbounded list blending into the rest of the page.
  Widget _boxedList({required Widget child, double maxHeight = 260}) => Container(
        constraints: BoxConstraints(maxHeight: maxHeight),
        decoration: BoxDecoration(border: Border.all(color: context.lineColor), borderRadius: BorderRadius.circular(10)),
        clipBehavior: Clip.antiAlias,
        child: child,
      );

  Widget _recipientTabBody() {
    if (_session == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text('Pick a WhatsApp session above first.', style: TextStyle(color: context.mutedColor, fontSize: 12.5)),
      );
    }
    return switch (_rTab) {
      _RTab.personal => _personalTab(),
      _RTab.group => _groupTab(),
      _RTab.csv => _csvTab(),
      _RTab.label => _labelTab(),
      _RTab.chat => _chatTab(),
    };
  }

  Widget _personalTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _personalSearchCtrl,
          onChanged: _onPersonalSearchChanged,
          decoration: const InputDecoration(hintText: 'Search contacts by name or phone…', prefixIcon: Icon(Icons.search_rounded)),
        ),
        if (_personalLoading) const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator())),
        if (!_personalLoading && _personalResults.isNotEmpty)
          _boxedList(
            child: ListView(
              shrinkWrap: true,
              // A checkbox per result — checking adds it, unchecking removes it — rather than a
              // one-shot tap-to-add: lets several contacts be picked from one search without
              // leaving the tab, and doubles as the "remove" control for ones already added.
              children: _personalResults.map((c) {
                final phone = str(c['phone'], '');
                final id = 'contact-${c['id']}';
                final already = _recipients.any((r) => r.id == id);
                return CheckboxListTile(
                  dense: true,
                  value: already,
                  onChanged: (v) {
                    if (v == true) {
                      _addRecipients([CampaignRecipient(id: id, name: str(c['name'], phone), phone: phone, type: 'personal', category: 'Personal')]);
                    } else {
                      setState(() => _recipients = _recipients.where((r) => r.id != id).toList());
                    }
                  },
                  title: Text(str(c['name'], phone), style: const TextStyle(fontSize: 13)),
                  subtitle: Text(phone, style: const TextStyle(fontSize: 11)),
                );
              }).toList(),
            ),
          ),
        const SizedBox(height: 10),
        Text('Add an unsaved number', style: TextStyle(fontSize: 12, color: context.mutedColor)),
        const SizedBox(height: 4),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _manualNumberCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(hintText: '+91XXXXXXXXXX', isDense: true),
              onSubmitted: (_) => _addManualNumber(),
            ),
          ),
          IconButton(onPressed: _addManualNumber, icon: const Icon(Icons.add_circle_rounded)),
        ]),
      ],
    );
  }

  Widget _groupTab() {
    final groups = _groups ?? [];
    final q = _groupSearchCtrl.text.trim().toLowerCase();
    final filtered = q.isEmpty ? groups : groups.where((g) => str(g['name'], '').toLowerCase().contains(q)).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _groupSearchCtrl,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(hintText: 'Search groups…', prefixIcon: Icon(Icons.search_rounded)),
        ),
        if (_groupsLoading) const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator())),
        if (!_groupsLoading)
          _boxedList(
            child: ListView(
              shrinkWrap: true,
              children: filtered.map((g) {
                final id = str(g['id'], '');
                final sel = _selectedGroupIds.contains(id);
                return CheckboxListTile(
                  dense: true,
                  value: sel,
                  onChanged: (v) => setState(() => v == true ? _selectedGroupIds.add(id) : _selectedGroupIds.remove(id)),
                  title: Text(str(g['name'], 'Group'), style: const TextStyle(fontSize: 13)),
                );
              }).toList(),
            ),
          ),
        if (_selectedGroupIds.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: FilledButton(
              onPressed: _resolvingGroupMembers ? null : _addGroupMembers,
              child: _resolvingGroupMembers
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text('Add members from ${_selectedGroupIds.length} group(s)'),
            ),
          ),
      ],
    );
  }

  Widget _csvTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _pickCsv,
              icon: const Icon(Icons.upload_file_rounded, size: 18),
              label: Text(_csvFileName ?? 'Choose CSV file', overflow: TextOverflow.ellipsis),
            ),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: _shareSampleCsv,
            icon: const Icon(Icons.description_outlined, size: 16),
            label: const Text('Sample'),
          ),
        ]),
        const SizedBox(height: 6),
        Text('Format: phone,name — e.g. +919876543210,John Doe',
            style: TextStyle(fontSize: 11, color: context.mutedColor)),
        if (_csvValid.isNotEmpty || _csvInvalidCount > 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('${_csvValid.length} valid, $_csvInvalidCount invalid',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        if (_csvValid.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: FilledButton(
              onPressed: () {
                _addRecipients(_csvValid);
                setState(() { _csvValid = []; _csvInvalidCount = 0; _csvFileName = null; });
              },
              child: Text('Add ${_csvValid.length} contacts'),
            ),
          ),
      ],
    );
  }

  Widget _labelTab() {
    final labels = _labels ?? [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_labelsLoading) const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator())),
        if (!_labelsLoading)
          _boxedList(
            child: ListView(
              shrinkWrap: true,
              children: labels.map((l) {
                final id = l['id'];
                final sel = _selectedLabelIds.contains(id);
                final count = l['contacts_count'];
                return CheckboxListTile(
                  dense: true,
                  value: sel,
                  onChanged: (v) => setState(() => v == true ? _selectedLabelIds.add(id) : _selectedLabelIds.remove(id)),
                  title: Text(str(l['name']), style: const TextStyle(fontSize: 13)),
                  subtitle: count != null ? Text('$count contact${count == 1 ? '' : 's'}', style: const TextStyle(fontSize: 11)) : null,
                );
              }).toList(),
            ),
          ),
        if (_selectedLabelIds.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: FilledButton(
              onPressed: _resolvingLabelContacts ? null : _addLabelContacts,
              child: _resolvingLabelContacts
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text('Add contacts from ${_selectedLabelIds.length} label(s)'),
            ),
          ),
      ],
    );
  }

  Widget _chatTab() {
    final chats = _chats ?? [];
    final q = _chatSearchCtrl.text.trim().toLowerCase();
    final filtered = q.isEmpty ? chats : chats.where((c) => str(c['name'], '').toLowerCase().contains(q)).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _chatSearchCtrl,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(hintText: 'Search chats…', prefixIcon: Icon(Icons.search_rounded)),
        ),
        if (_chatsLoading) const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator())),
        if (!_chatsLoading)
          _boxedList(
            child: ListView(
              shrinkWrap: true,
              children: filtered.map((c) {
                final id = str(c['id'], '');
                final sel = _selectedChatIds.contains(id);
                return CheckboxListTile(
                  dense: true,
                  value: sel,
                  onChanged: (v) => setState(() => v == true ? _selectedChatIds.add(id) : _selectedChatIds.remove(id)),
                  title: Text(str(c['name'], id), style: const TextStyle(fontSize: 13)),
                  secondary: Icon(c['isGroup'] == true ? Icons.groups_rounded : Icons.person_rounded, size: 18),
                );
              }).toList(),
            ),
          ),
        if (_selectedChatIds.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: FilledButton(onPressed: _addSelectedChats, child: Text('Add ${_selectedChatIds.length} chat(s)')),
          ),
      ],
    );
  }

  // ── Message tab shell ────────────────────────────────────────────────────

  Widget _messageTabBar() => Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          _chip('✏️ Text', _mTab == _MTab.text, () => setState(() => _mTab = _MTab.text)),
          _chip('📎 Multi Media', _mTab == _MTab.media, () => setState(() => _mTab = _MTab.media)),
          _chip('📋 Template', _mTab == _MTab.template, () {
            setState(() => _mTab = _MTab.template);
            if (_templates == null) _loadTemplates();
          }),
          _chip('📊 Poll', _mTab == _MTab.poll, () => setState(() => _mTab = _MTab.poll)),
          _chip('📍 Location', _mTab == _MTab.location, () => setState(() => _mTab = _MTab.location)),
          _chip('👤 Contact', _mTab == _MTab.contact, () {
            setState(() => _mTab = _MTab.contact);
            if (_sessionContacts == null) _loadSessionContacts();
          }),
          _chip('🎤 Audio', _mTab == _MTab.audio, () => setState(() => _mTab = _MTab.audio)),
        ],
      );

  Widget _messageTabBody() => switch (_mTab) {
        _MTab.text => _textTab(),
        _MTab.media => _mediaTab(),
        _MTab.template => _templateTab(),
        _MTab.poll => _pollTab(),
        _MTab.location => _locationTab(),
        _MTab.contact => _contactTab(),
        _MTab.audio => _audioTab(),
      };

  Widget _textTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          IconButton(tooltip: 'Bold', onPressed: () => _wrapSelection('*'), icon: const Icon(Icons.format_bold_rounded, size: 20)),
          IconButton(tooltip: 'Italic', onPressed: () => _wrapSelection('_'), icon: const Icon(Icons.format_italic_rounded, size: 20)),
          IconButton(tooltip: 'Strikethrough', onPressed: () => _wrapSelection('~'), icon: const Icon(Icons.strikethrough_s_rounded, size: 20)),
          IconButton(tooltip: 'Emoji', onPressed: _showEmojiPicker, icon: const Icon(Icons.emoji_emotions_outlined, size: 20)),
        ]),
        TextField(
          controller: _textCtrl,
          maxLines: 6,
          minLines: 4,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            hintText: 'Type your message… *bold* _italic_ ~strike~ {{name}} {{phone}} {{date}} {{time}}',
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: Text('${_textCtrl.text.length} chars', style: TextStyle(fontSize: 11, color: context.mutedColor)),
        ),
        Text('Variables: {{name}} {{phone}} {{date}} {{time}} {{company_details}} {{company_number}}',
            style: TextStyle(fontSize: 11, color: context.mutedColor)),
      ],
    );
  }

  void _wrapSelection(String marker) {
    final text = _textCtrl.text;
    final sel = _textCtrl.selection;
    final start = sel.start < 0 ? text.length : sel.start;
    final end = sel.end < 0 ? text.length : sel.end;
    final selected = text.substring(start, end);
    final newText = text.replaceRange(start, end, '$marker$selected$marker');
    _textCtrl.value = TextEditingValue(
      text: newText,
      selection: selected.isEmpty
          ? TextSelection.collapsed(offset: start + marker.length)
          : TextSelection(baseOffset: start, extentOffset: start + marker.length * 2 + selected.length),
    );
    setState(() {});
  }

  static const _commonEmoji = [
    '😀', '😂', '😊', '😍', '🙏', '👍', '🎉', '❤️', '🔥', '✅',
    '🙌', '😎', '🤝', '💯', '📅', '⏰', '📍', '🎁', '💰', '📢',
  ];

  void _showEmojiPicker() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _commonEmoji
                .map((e) => InkWell(
                      onTap: () {
                        final sel = _textCtrl.selection;
                        final pos = sel.start < 0 ? _textCtrl.text.length : sel.start;
                        _textCtrl.text = _textCtrl.text.replaceRange(pos, pos, e);
                        _textCtrl.selection = TextSelection.collapsed(offset: pos + e.length);
                        setState(() {});
                        Navigator.pop(ctx);
                      },
                      child: Text(e, style: const TextStyle(fontSize: 26)),
                    ))
                .toList(),
          ),
        ),
      ),
    );
  }

  Widget _mediaTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < _mediaBlocks.length; i++) _mediaBlockCard(_mediaBlocks[i], i),
        OutlinedButton.icon(
          onPressed: () => setState(() => _mediaBlocks.add(CampaignMediaBlock(type: 'image'))),
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Add block'),
        ),
      ],
    );
  }

  Widget _mediaBlockCard(CampaignMediaBlock block, int index) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(border: Border.all(color: context.lineColor), borderRadius: BorderRadius.circular(8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: block.type,
                isDense: true,
                items: const [
                  DropdownMenuItem(value: 'text', child: Text('Text')),
                  DropdownMenuItem(value: 'image', child: Text('Image')),
                  DropdownMenuItem(value: 'video', child: Text('Video')),
                  DropdownMenuItem(value: 'audio', child: Text('Audio')),
                  DropdownMenuItem(value: 'document', child: Text('Document')),
                ],
                onChanged: (v) => setState(() => block.type = v ?? 'text'),
              ),
            ),
            IconButton(
              onPressed: () => setState(() => _mediaBlocks.removeAt(index)),
              icon: const Icon(Icons.delete_outline_rounded, color: AppPalette.danger, size: 20),
            ),
          ]),
          if (block.type == 'text')
            TextField(
              maxLines: 3,
              onChanged: (v) => block.text = v,
              controller: TextEditingController(text: block.text),
              decoration: const InputDecoration(hintText: 'Text for this block…', isDense: true),
            )
          else ...[
            Row(children: [
              Expanded(
                child: TextField(
                  onChanged: (v) => setState(() => block.mediaUrl = v),
                  controller: TextEditingController(text: block.mediaUrl),
                  decoration: const InputDecoration(hintText: 'Media URL', isDense: true),
                ),
              ),
            ]),
            Row(children: [
              TextButton.icon(
                onPressed: () => _pickMediaBlockFile(block),
                icon: const Icon(Icons.upload_file_rounded, size: 16),
                label: const Text('Upload'),
              ),
              TextButton.icon(
                onPressed: () => _browseLibrary(block),
                icon: const Text('🗂️', style: TextStyle(fontSize: 14)),
                label: const Text('Browse Library'),
              ),
            ]),
            if (block.type != 'audio')
              TextField(
                onChanged: (v) => block.caption = v,
                controller: TextEditingController(text: block.caption),
                decoration: const InputDecoration(hintText: 'Caption (optional)', isDense: true),
              ),
          ],
        ],
      ),
    );
  }

  Widget _templateTab() {
    if (_templatesLoading) return const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator()));
    final templates = _templates ?? [];
    if (templates.isEmpty) {
      return Text('No templates yet.', style: TextStyle(color: context.mutedColor, fontSize: 12.5));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<Rec>(
          initialValue: _selectedTemplate,
          isExpanded: true,
          hint: const Text('Choose a template'),
          items: templates
              .map((t) => DropdownMenuItem(value: t, child: Text(str(t['name'], 'Template'), overflow: TextOverflow.ellipsis)))
              .toList(),
          onChanged: (t) => setState(() => _selectedTemplate = t),
        ),
        if (_selectedTemplate != null)
          Container(
            margin: const EdgeInsets.only(top: 10),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: context.altSurface, borderRadius: BorderRadius.circular(8)),
            child: Text(
              _templateIsMedia ? '📎 ${str(_selectedTemplate!['header_type'], 'media')} message' : str(_selectedTemplate!['body'], ''),
              style: const TextStyle(fontSize: 13),
            ),
          ),
      ],
    );
  }

  Widget _pollTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(controller: _pollQuestionCtrl, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'Question')),
        const SizedBox(height: 10),
        for (var i = 0; i < _pollOptionCtrls.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _pollOptionCtrls[i],
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(labelText: 'Option ${i + 1}', isDense: true),
                ),
              ),
              if (_pollOptionCtrls.length > 2)
                IconButton(
                  onPressed: () => setState(() => _pollOptionCtrls.removeAt(i).dispose()),
                  icon: const Icon(Icons.remove_circle_outline_rounded, size: 20),
                ),
            ]),
          ),
        if (_pollOptionCtrls.length < 12)
          TextButton.icon(
            onPressed: () => setState(() => _pollOptionCtrls.add(TextEditingController())),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Add option'),
          ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _pollAllowMultiple,
          onChanged: (v) => setState(() => _pollAllowMultiple = v),
          title: const Text('Allow multiple answers', style: TextStyle(fontSize: 13)),
        ),
      ],
    );
  }

  Widget _locationTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Expanded(
            child: TextField(
              controller: _latCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Latitude', isDense: true),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _lngCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Longitude', isDense: true),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _locatingDevice ? null : _useCurrentLocation,
          icon: _locatingDevice
              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.my_location_rounded, size: 18),
          label: const Text('Use my current location'),
        ),
        const SizedBox(height: 8),
        TextField(controller: _locNameCtrl, decoration: const InputDecoration(labelText: 'Name (optional)', isDense: true)),
        const SizedBox(height: 8),
        TextField(controller: _locAddrCtrl, decoration: const InputDecoration(labelText: 'Address (optional)', isDense: true)),
      ],
    );
  }

  Widget _contactTab() {
    if (_session == null) {
      return Text('Pick a WhatsApp session above first.', style: TextStyle(color: context.mutedColor, fontSize: 12.5));
    }
    if (_pickedContact != null) {
      final c = _pickedContact!;
      return Row(children: [
        Expanded(child: Text('${str(c['name'] ?? c['pushName'], str(c['number'], ''))} · ${str(c['number'], '')}', style: const TextStyle(fontSize: 13))),
        TextButton(onPressed: () => setState(() => _pickedContact = null), child: const Text('Change')),
      ]);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _contactSearchCtrl,
          onChanged: _onContactSearchChanged,
          decoration: const InputDecoration(hintText: 'Search this session\'s contacts…', prefixIcon: Icon(Icons.search_rounded)),
        ),
        if (_sessionContactsLoading) const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator())),
        if (!_sessionContactsLoading)
          _boxedList(
            child: ListView(
              shrinkWrap: true,
              children: _contactResults
                  .map((c) => ListTile(
                        dense: true,
                        title: Text(str(c['name'] ?? c['pushName'], str(c['number'], '')), style: const TextStyle(fontSize: 13)),
                        subtitle: Text(str(c['number'], ''), style: const TextStyle(fontSize: 11)),
                        onTap: () => setState(() => _pickedContact = c),
                      ))
                  .toList(),
            ),
          ),
      ],
    );
  }

  // A single, stable Row shape at all times — only the leading icon, status text and trailing
  // control vary — rather than three structurally different Rows swapped in and out, which is the
  // same class of shape-change that can trip Flutter's semantics-tree assertions during rapid
  // state changes (see the note on contact_info_page.dart's tab bodies for the fuller story).
  Widget _audioTab() {
    final ready = _audioUrl != null;
    final statusText = ready
        ? 'Recording ready'
        : _uploadingAudio
            ? 'Uploading…'
            : _recording
                ? '${_audioElapsed.inMinutes}:${(_audioElapsed.inSeconds % 60).toString().padLeft(2, '0')}'
                : 'Not recording';
    return Row(
      children: [
        Icon(
          ready ? Icons.check_circle_rounded : Icons.mic_rounded,
          color: ready ? AppPalette.success : (_recording ? AppPalette.danger : context.mutedColor),
          size: 20,
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(statusText)),
        if (_uploadingAudio)
          const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
        else if (ready)
          TextButton(onPressed: () => setState(() => _audioUrl = null), child: const Text('Re-record'))
        else
          FilledButton.icon(
            onPressed: _recording ? _stopAndUploadRecording : _startRecording,
            icon: Icon(_recording ? Icons.stop_rounded : Icons.fiber_manual_record_rounded, size: 18),
            label: Text(_recording ? 'Stop' : 'Record'),
          ),
      ],
    );
  }

  // ── Sending options ──────────────────────────────────────────────────────

  /// Session picker — deliberately the FIRST thing on the page (see build()): Personal/Group/
  /// From-Chat recipients and the session-sourced Contact tab all depend on which session is
  /// picked, so it has to be chosen before any of those make sense to show.
  Widget _sessionPicker() {
    final async = ref.watch(wahaSessionsProvider);
    return async.when(
      loading: () => const LinearProgressIndicator(),
      error: (e, _) => Text("Couldn't load sessions — ${apiErrorMessage(e)}", style: const TextStyle(fontSize: 12, color: AppPalette.danger)),
      data: (sessions) {
        // Matches chats_page.dart's _connectedStatuses exactly — a session can report any of
        // these for "actually usable", not just the literal string 'ready'. Checking only
        // 'ready' here meant a live session sitting at e.g. 'connected' or 'authenticated'
        // fell through to the unfiltered `sessions` fallback below and could lose the pick to
        // a genuinely dead one, silently breaking every session-scoped fetch (groups, chats,
        // contacts) for no visible reason.
        final ready = sessions.where((s) => _connectedStatuses.contains(str(s['status'], '').toLowerCase())).toList();
        final options = ready.isNotEmpty ? ready : sessions;
        if (_session == null && options.isNotEmpty) {
          // Routed through _onSessionChanged (not a bare setState) so it also fires whichever
          // session-scoped load (groups/chats/session contacts) the active tab needs. Without
          // this, a tab tapped before this callback runs saw `_session == null`, its load
          // bailed out silently, and nothing ever re-triggered it once `_session` did land —
          // the tab just sat empty forever, looking like "groups/chats/contacts not fetching".
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _session == null) _onSessionChanged(options.first);
          });
        }
        if (options.isEmpty) {
          return Text('No connected sessions yet.', style: TextStyle(color: context.mutedColor, fontSize: 12.5));
        }
        final sel = _session != null && options.any((s) => s['id'] == _session!['id']) ? _session : options.first;
        return DropdownButtonFormField<int>(
          initialValue: sel?['id'] as int?,
          isExpanded: true,
          items: options.map((s) {
            final label = str(s['display_name'] ?? s['phone'] ?? s['session_name'], 'Session');
            final phone = str(s['phone'], '');
            return DropdownMenuItem(value: s['id'] as int?, child: Text(phone.isNotEmpty && phone != label ? '$label ($phone)' : label));
          }).toList(),
          onChanged: (id) => _onSessionChanged(options.firstWhere((s) => s['id'] == id, orElse: () => options.first)),
        );
      },
    );
  }

  /// Every session-scoped list (groups, chats, the session's own contact book) belongs to
  /// whichever session was picked when it was fetched — switching sessions makes all of it stale,
  /// so it's dropped rather than shown as if it still applies to the new one.
  void _onSessionChanged(Rec newSession) {
    if (_session != null && _session!['id'] == newSession['id']) return;
    setState(() {
      _session = newSession;
      _groups = null;
      _selectedGroupIds.clear();
      _chats = null;
      _selectedChatIds.clear();
      _sessionContacts = null;
      _pickedContact = null;
      _contactSearchCtrl.clear();
      _contactResults = [];
    });
    // Re-fetch for whichever session-scoped recipient/message tab is already open — otherwise it
    // would just sit empty until the user happens to tap away and back.
    if (_rTab == _RTab.group) _loadGroups();
    if (_rTab == _RTab.chat) _loadChats();
    if (_mTab == _MTab.contact) _loadSessionContacts();
  }

  Widget _sendingOptions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Delay between messages: ${_delaySeconds.round()}s', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: context.mutedColor)),
        Slider(
          value: _delaySeconds,
          min: 1,
          max: 60,
          divisions: 59,
          label: '${_delaySeconds.round()}s',
          onChanged: (v) => setState(() => _delaySeconds = v),
        ),
        const SizedBox(height: 8),
        Text('Schedule (optional)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: context.mutedColor)),
        const SizedBox(height: 4),
        Row(children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _pickScheduleDateTime,
              child: Text(_scheduledAt == null ? 'dd/mm/yyyy, --:-- --' : when(_scheduledAt!.toIso8601String())),
            ),
          ),
          if (_scheduledAt != null)
            IconButton(onPressed: () => setState(() => _scheduledAt = null), icon: const Icon(Icons.close_rounded)),
        ]),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _uniqueSignature,
          onChanged: (v) => setState(() => _uniqueSignature = v),
          title: const Text('Anti-spam Signature', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          subtitle: const Text('Appends invisible unique Unicode characters per recipient, reducing WhatsApp bulk-detection risk.',
              style: TextStyle(fontSize: 11)),
        ),
      ],
    );
  }

  Future<void> _pickScheduleDateTime() async {
    final now = DateTime.now();
    final date = await showDatePicker(context: context, initialDate: now, firstDate: now, lastDate: now.add(const Duration(days: 365)));
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(now.add(const Duration(minutes: 5))));
    if (time == null) return;
    setState(() => _scheduledAt = DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }
}
