// The WA Chat message composer's "+" attachment sheet — mirrors WhatsApp's own attachment picker
// (Camera / Gallery / Document / Audio / Location) plus one addition specific to this app: sharing
// a single Catalog listing (a course/service/product from the company's own catalog, see
// growth_pages.dart's ListingsPage) as a ready-to-send message in one tap.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:unichat_mobile_app/core/constants/app_colors.dart';
import 'package:unichat_mobile_app/core/network/wa_chat_api_service.dart';
import 'package:unichat_mobile_app/features/modules/_shared.dart';

/// Shows the attachment sheet and sends whatever the user picks. Returns true if a message was
/// actually sent (so the caller can refresh the thread), false if the sheet was dismissed or the
/// send failed (an error is already surfaced to the user before returning in that case).
Future<bool> showWaAttachmentSheet(
  BuildContext context, {
  required String sessionName,
  required String apiKey,
  required String chatId,
}) async {
  final action = await showModalBottomSheet<_AttachAction>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => _AttachmentGrid(),
  );
  if (action == null || !context.mounted) return false;

  try {
    switch (action) {
      case _AttachAction.camera:
        return await _pickAndSendImage(context, sessionName, apiKey, chatId, ImageSource.camera);
      case _AttachAction.gallery:
        return await _pickAndSendImage(context, sessionName, apiKey, chatId, ImageSource.gallery);
      case _AttachAction.video:
        return await _pickAndSendVideo(context, sessionName, apiKey, chatId);
      case _AttachAction.document:
        return await _pickAndSendDocument(context, sessionName, apiKey, chatId);
      case _AttachAction.audio:
        return await _pickAndSendAudio(context, sessionName, apiKey, chatId);
      case _AttachAction.voice:
        return await _recordAndSendAudio(context, sessionName, apiKey, chatId);
      case _AttachAction.location:
        return await _shareLocation(context, sessionName, apiKey, chatId);
      case _AttachAction.catalog:
        return await _shareCatalogItem(context, sessionName, apiKey, chatId);
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
    }
    return false;
  }
}

enum _AttachAction { camera, gallery, video, document, audio, voice, location, catalog }

class _AttachmentGrid extends StatelessWidget {
  const _AttachmentGrid();

  static const _items = <(_AttachAction, IconData, String, Color)>[
    (_AttachAction.camera, Icons.camera_alt_rounded, 'Camera', Color(0xFFE0475B)),
    (_AttachAction.gallery, Icons.image_rounded, 'Gallery', Color(0xFF8B5CF6)),
    (_AttachAction.video, Icons.videocam_rounded, 'Video', Color(0xFFEA580C)),
    (_AttachAction.document, Icons.insert_drive_file_rounded, 'Document', Color(0xFF2E9CCA)),
    (_AttachAction.audio, Icons.headphones_rounded, 'Audio file', Color(0xFF12A594)),
    (_AttachAction.voice, Icons.mic_rounded, 'Record voice', Color(0xFFDC2626)),
    (_AttachAction.location, Icons.location_on_rounded, 'Location', Color(0xFF16A34A)),
    (_AttachAction.catalog, Icons.storefront_rounded, 'Catalog', Color(0xFFD97706)),
  ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
        child: GridView.count(
          shrinkWrap: true,
          crossAxisCount: 4,
          mainAxisSpacing: 16,
          crossAxisSpacing: 8,
          childAspectRatio: 0.85,
          children: _items
              .map((item) => _AttachTile(icon: item.$2, label: item.$3, color: item.$4,
                  onTap: () => Navigator.pop(context, item.$1)))
              .toList(),
        ),
      ),
    );
  }
}

class _AttachTile extends StatelessWidget {
  const _AttachTile({required this.icon, required this.label, required this.color, required this.onTap});
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52, height: 52,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(fontSize: 11.5)),
        ],
      ),
    );
  }
}

// ── Caption dialog — shown after picking an image/video/document, matching WhatsApp's own
// preview-then-caption step before the message actually goes out. ─────────────────────────

Future<String?> _askCaption(BuildContext context, {required String title}) {
  final ctrl = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        maxLines: 3,
        minLines: 1,
        decoration: const InputDecoration(hintText: 'Add a caption (optional)'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Send')),
      ],
    ),
  );
}

Future<bool> _pickAndSendImage(
  BuildContext context, String sessionName, String apiKey, String chatId, ImageSource source) async {
  final file = await ImagePicker().pickImage(source: source, imageQuality: 85);
  if (file == null || !context.mounted) return false;
  final caption = await _askCaption(context, title: 'Send photo');
  if (caption == null || !context.mounted) return false;
  final bytes = await file.readAsBytes();
  await WaChatApiService.sendMedia(sessionName, apiKey,
      chatId: chatId,
      mediaType: 'image',
      base64: base64Encode(bytes),
      mimetype: lookupMimeType(file.path) ?? 'image/jpeg',
      filename: file.name,
      caption: caption.isEmpty ? null : caption);
  return true;
}

Future<bool> _pickAndSendVideo(BuildContext context, String sessionName, String apiKey, String chatId) async {
  final file = await ImagePicker().pickVideo(source: ImageSource.gallery);
  if (file == null || !context.mounted) return false;
  final caption = await _askCaption(context, title: 'Send video');
  if (caption == null || !context.mounted) return false;
  final bytes = await file.readAsBytes();
  await WaChatApiService.sendMedia(sessionName, apiKey,
      chatId: chatId,
      mediaType: 'video',
      base64: base64Encode(bytes),
      mimetype: lookupMimeType(file.path) ?? 'video/mp4',
      filename: file.name,
      caption: caption.isEmpty ? null : caption);
  return true;
}

Future<bool> _pickAndSendDocument(BuildContext context, String sessionName, String apiKey, String chatId) async {
  final result = await FilePicker.platform.pickFiles(withData: true);
  final picked = result?.files.single;
  if (picked == null || picked.bytes == null || !context.mounted) return false;
  final caption = await _askCaption(context, title: 'Send document');
  if (caption == null || !context.mounted) return false;
  await WaChatApiService.sendMedia(sessionName, apiKey,
      chatId: chatId,
      mediaType: 'document',
      base64: base64Encode(picked.bytes!),
      mimetype: lookupMimeType(picked.name) ?? 'application/octet-stream',
      filename: picked.name,
      caption: caption.isEmpty ? null : caption);
  return true;
}

/// Picks an EXISTING audio file and sends it. Live recording is the separate "Record voice" tile.
Future<bool> _pickAndSendAudio(BuildContext context, String sessionName, String apiKey, String chatId) async {
  final result = await FilePicker.platform.pickFiles(type: FileType.audio, withData: true);
  final picked = result?.files.single;
  if (picked == null || picked.bytes == null) return false;
  await WaChatApiService.sendMedia(sessionName, apiKey,
      chatId: chatId,
      mediaType: 'audio',
      base64: base64Encode(picked.bytes!),
      mimetype: lookupMimeType(picked.name) ?? 'audio/mpeg',
      filename: picked.name);
  return true;
}

/// Records a voice note (tap to stop, or discard) and sends it as an audio message. The gateway's
/// single-message send API has no separate "voice note" endpoint/flag (only the bulk-send payload
/// carries a `ptt` marker) — sent via the same send-audio route as a picked file, so it may render
/// as a regular audio attachment rather than a native voice-note waveform bubble on WhatsApp.
Future<bool> _recordAndSendAudio(BuildContext context, String sessionName, String apiKey, String chatId) async {
  final path = await showModalBottomSheet<String>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    builder: (ctx) => const _VoiceRecorderSheet(),
  );
  if (path == null || !context.mounted) return false;
  final bytes = await File(path).readAsBytes();
  await WaChatApiService.sendMedia(sessionName, apiKey,
      chatId: chatId, mediaType: 'audio', base64: base64Encode(bytes), mimetype: 'audio/m4a', filename: 'voice-note.m4a');
  return true;
}

class _VoiceRecorderSheet extends StatefulWidget {
  const _VoiceRecorderSheet();
  @override
  State<_VoiceRecorderSheet> createState() => _VoiceRecorderSheetState();
}

class _VoiceRecorderSheetState extends State<_VoiceRecorderSheet> {
  final _recorder = AudioRecorder();
  bool _recording = false;
  bool _denied = false;
  Duration _elapsed = Duration.zero;
  Timer? _timer;
  String? _path;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    if (!await _recorder.hasPermission()) {
      if (mounted) setState(() => _denied = true);
      return;
    }
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(const RecordConfig(), path: path);
    if (!mounted) return;
    _path = path;
    setState(() => _recording = true);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsed += const Duration(seconds: 1));
    });
  }

  Future<void> _stopAndSend() async {
    _timer?.cancel();
    final stoppedPath = await _recorder.stop();
    if (mounted) Navigator.pop(context, stoppedPath ?? _path);
  }

  Future<void> _cancel() async {
    _timer?.cancel();
    if (_recording) await _recorder.stop();
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  String _fmt(Duration d) => '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    if (_denied) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Microphone permission is required to record a voice note.'),
            const SizedBox(height: 12),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
          ]),
        ),
      );
    }
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.mic_rounded, size: 48, color: _recording ? AppColors.error : AppColors.textLight),
            const SizedBox(height: 12),
            Text(_fmt(_elapsed), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(_recording ? 'Recording…' : 'Starting…', style: const TextStyle(color: AppColors.textLight)),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  onPressed: _cancel,
                  icon: const Icon(Icons.delete_outline_rounded, color: AppColors.error),
                  iconSize: 32,
                  tooltip: 'Discard',
                ),
                FloatingActionButton(
                  onPressed: _recording ? _stopAndSend : null,
                  backgroundColor: AppColors.primary,
                  child: const Icon(Icons.send_rounded, color: Colors.white),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

Future<bool> _shareLocation(BuildContext context, String sessionName, String apiKey, String chatId) async {
  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Location permission is required to share your location.')));
    }
    return false;
  }
  if (!await Geolocator.isLocationServiceEnabled()) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Turn on location services first.')));
    }
    return false;
  }
  final position = await Geolocator.getCurrentPosition();
  await WaChatApiService.sendLocation(sessionName, apiKey,
      chatId: chatId, latitude: position.latitude, longitude: position.longitude);
  return true;
}

/// The one non-WhatsApp addition: share a single catalog listing (course/service/product) as a
/// ready-made message in one tap — an image+caption when the listing has a photo, otherwise a
/// plain formatted text message. Mirrors the same `/listings` data ListingsPage already lists.
Future<bool> _shareCatalogItem(BuildContext context, String sessionName, String apiKey, String chatId) async {
  List<Rec> listings;
  try {
    listings = await Api.list('/listings');
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Couldn't load catalog — ${apiErrorMessage(e)}")));
    }
    return false;
  }
  if (!context.mounted) return false;
  if (listings.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No catalog items yet — add one under Listings & Products.')));
    return false;
  }

  final picked = await showModalBottomSheet<Rec>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => DraggableScrollableSheet(
      initialChildSize: 0.6,
      expand: false,
      builder: (ctx, scrollCtrl) => ListView.separated(
        controller: scrollCtrl,
        padding: const EdgeInsets.all(16),
        itemCount: listings.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final l = listings[i];
          return RecordCard(
            title: str(l['title'] ?? l['name']),
            subtitle: str(l['description'], ''),
            leadingIcon: Icons.inventory_2_rounded,
            leadingColor: const Color(0xFFEA580C),
            trailing: l['price'] != null ? Text(money(l['price']), style: const TextStyle(fontWeight: FontWeight.w800)) : null,
            onTap: () => Navigator.pop(ctx, l),
          );
        },
      ),
    ),
  );
  if (picked == null || !context.mounted) return false;

  final title = str(picked['title'] ?? picked['name'], 'Item');
  final description = str(picked['description'], '');
  final price = picked['price'];
  final caption = [
    '*$title*',
    if (description.isNotEmpty) description,
    if (price != null) money(price),
  ].join('\n\n');

  final imageUrl = _firstListingImageUrl(picked['media']);
  if (imageUrl != null) {
    await WaChatApiService.sendMedia(sessionName, apiKey,
        chatId: chatId, mediaType: 'image', url: imageUrl, caption: caption);
  } else {
    await WaChatApiService.sendText(sessionName, apiKey, chatId, caption);
  }
  return true;
}

/// `Listing.media` is a JSON array whose entries have shown up as either a bare URL string or an
/// object carrying one — handle both rather than assuming a single shape.
String? _firstListingImageUrl(Object? media) {
  if (media is! List || media.isEmpty) return null;
  final first = media.first;
  if (first is String && first.isNotEmpty) return first;
  if (first is Map) {
    final url = first['url'] ?? first['path'] ?? first['src'];
    if (url is String && url.isNotEmpty) return url;
  }
  return null;
}
