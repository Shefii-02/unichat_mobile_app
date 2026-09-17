// Media rendering for WhatsAppBubble — image/video/audio/document, all delivered inline as base64
// under `metadata.media.data` (see GET .../messages and .../messages/:chatId/history). Nothing
// here is cached beyond one temp file per widget instance: video/audio need a real file on disk
// (video_player/audioplayers don't play raw bytes directly), so the base64 payload is decoded and
// written to the temp dir the first time each bubble plays.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

const _mediaMessageTypes = {'image', 'video', 'audio', 'voice', 'sticker', 'document'};

bool isMediaMessageType(String type) => _mediaMessageTypes.contains(type);

/// Dispatches on message `type` to the right media widget, or a placeholder when the payload
/// wasn't downloaded (`omitted: true` — past the inline-media size budget) or failed to decode.
Widget buildMediaContent(String type, Map<String, dynamic>? media, Color textColor) {
  if (media == null) return _placeholder(type, null, null, textColor);
  final data = media['data'] as String?;
  final omitted = media['omitted'] == true;
  final filename = media['filename'] as String?;
  final mimetype = media['mimetype'] as String? ?? '';
  final sizeBytes = media['sizeBytes'];

  if (omitted || data == null || data.isEmpty) {
    return _placeholder(type, filename, sizeBytes, textColor);
  }

  switch (type) {
    case 'image':
    case 'sticker':
      return _ImageMedia(base64Data: data, textColor: textColor);
    case 'video':
      return _VideoMedia(base64Data: data, mimetype: mimetype, textColor: textColor);
    case 'audio':
    case 'voice':
      return _AudioMedia(base64Data: data, mimetype: mimetype, textColor: textColor);
    default:
      return _DocumentMedia(
          base64Data: data, filename: filename, mimetype: mimetype, sizeBytes: sizeBytes, textColor: textColor);
  }
}

Future<File> _writeTempFile(String base64Data, String extension) async {
  final bytes = base64Decode(base64Data);
  final dir = await getTemporaryDirectory();
  // Keyed by content hash, not a random name — replaying the same message (e.g. after a reload)
  // reuses the file on disk instead of writing a fresh multi-MB copy every time it's opened.
  final file = File('${dir.path}/wa_media_${bytes.hashCode}.$extension');
  if (!await file.exists()) {
    await file.writeAsBytes(bytes, flush: true);
  }
  return file;
}

String _extFromMimetype(String mimetype, {String fallback = 'bin'}) =>
    mimetype.contains('/') ? mimetype.split('/').last.split(';').first : fallback;

Widget _placeholder(String type, String? filename, Object? sizeBytes, Color textColor) {
  final icon = switch (type) {
    'image' || 'sticker' => Icons.image_rounded,
    'video' => Icons.videocam_rounded,
    'audio' || 'voice' => Icons.mic_rounded,
    'document' => Icons.insert_drive_file_rounded,
    _ => Icons.attachment_rounded,
  };
  final label = filename ?? 'Media unavailable';
  return Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(8)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, color: textColor.withValues(alpha: 0.7)),
      const SizedBox(width: 8),
      Flexible(
        child: Text(label,
            maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: textColor.withValues(alpha: 0.7), fontSize: 12)),
      ),
    ]),
  );
}

// ── Image / sticker ──────────────────────────────────────────────────────────

class _ImageMedia extends StatelessWidget {
  const _ImageMedia({required this.base64Data, required this.textColor});
  final String base64Data;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    Uint8List? bytes;
    try {
      bytes = base64Decode(base64Data);
    } catch (_) {}
    if (bytes == null) return _placeholder('image', null, null, textColor);
    final decoded = bytes;
    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(backgroundColor: Colors.black, iconTheme: const IconThemeData(color: Colors.white)),
          body: Center(child: InteractiveViewer(child: Image.memory(decoded))),
        ),
      )),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.memory(
          decoded,
          fit: BoxFit.cover,
          width: 220,
          height: 220,
          errorBuilder: (_, __, ___) => _placeholder('image', null, null, textColor),
        ),
      ),
    );
  }
}

// ── Video ─────────────────────────────────────────────────────────────────────

class _VideoMedia extends StatefulWidget {
  const _VideoMedia({required this.base64Data, required this.mimetype, required this.textColor});
  final String base64Data;
  final String mimetype;
  final Color textColor;

  @override
  State<_VideoMedia> createState() => _VideoMediaState();
}

class _VideoMediaState extends State<_VideoMedia> {
  VideoPlayerController? _controller;
  bool _initializing = false;
  bool _failed = false;

  Future<void> _play() async {
    final controller = _controller;
    if (controller != null) {
      setState(() => controller.value.isPlaying ? controller.pause() : controller.play());
      return;
    }
    setState(() => _initializing = true);
    try {
      final file = await _writeTempFile(widget.base64Data, _extFromMimetype(widget.mimetype, fallback: 'mp4'));
      final c = VideoPlayerController.file(file);
      await c.initialize();
      if (!mounted) return;
      c.addListener(() => mounted ? setState(() {}) : null);
      setState(() { _controller = c; _initializing = false; });
      c.play();
    } catch (_) {
      if (!mounted) return;
      setState(() { _initializing = false; _failed = true; });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) return _placeholder('video', null, null, widget.textColor);
    final c = _controller;
    if (c != null && c.value.isInitialized) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 220,
          child: AspectRatio(
            aspectRatio: c.value.aspectRatio == 0 ? 16 / 9 : c.value.aspectRatio,
            child: GestureDetector(
              onTap: _play,
              child: Stack(alignment: Alignment.center, children: [
                VideoPlayer(c),
                if (!c.value.isPlaying)
                  const Icon(Icons.play_circle_fill_rounded, size: 48, color: Colors.white70),
              ]),
            ),
          ),
        ),
      );
    }
    return GestureDetector(
      onTap: _play,
      child: Container(
        width: 220,
        height: 140,
        decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(8)),
        child: Center(
          child: _initializing
              ? const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70))
              : const Icon(Icons.play_circle_fill_rounded, size: 48, color: Colors.white70),
        ),
      ),
    );
  }
}

// ── Audio / voice note ─────────────────────────────────────────────────────────

class _AudioMedia extends StatefulWidget {
  const _AudioMedia({required this.base64Data, required this.mimetype, required this.textColor});
  final String base64Data;
  final String mimetype;
  final Color textColor;

  @override
  State<_AudioMedia> createState() => _AudioMediaState();
}

class _AudioMediaState extends State<_AudioMedia> {
  final _player = AudioPlayer();
  bool _loading = false;
  bool _playing = false;
  bool _failed = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _player.onPositionChanged.listen((p) { if (mounted) setState(() => _position = p); });
    _player.onDurationChanged.listen((d) { if (mounted) setState(() => _duration = d); });
    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() { _playing = false; _position = Duration.zero; });
    });
  }

  Future<void> _toggle() async {
    if (_playing) {
      await _player.pause();
      if (mounted) setState(() => _playing = false);
      return;
    }
    setState(() => _loading = true);
    try {
      final file = await _writeTempFile(widget.base64Data, _extFromMimetype(widget.mimetype, fallback: 'mp3'));
      await _player.play(DeviceFileSource(file.path));
      if (!mounted) return;
      setState(() { _playing = true; _loading = false; });
    } catch (_) {
      if (!mounted) return;
      setState(() { _loading = false; _failed = true; });
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) return _placeholder('audio', null, null, widget.textColor);
    final totalMs = _duration.inMilliseconds;
    final progress = totalMs > 0 ? (_position.inMilliseconds / totalMs).clamp(0.0, 1.0) : 0.0;
    return SizedBox(
      width: 200,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _loading
              ? const Padding(
                  padding: EdgeInsets.all(6),
                  child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                )
              : IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: _toggle,
                  icon: Icon(_playing ? Icons.pause_circle_filled_rounded : Icons.play_circle_filled_rounded,
                      size: 32, color: widget.textColor),
                ),
          const SizedBox(width: 6),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(value: progress, minHeight: 3, backgroundColor: widget.textColor.withValues(alpha: 0.2)),
            ),
          ),
          const SizedBox(width: 6),
          Text(_fmt(_position.inMilliseconds > 0 ? _position : _duration),
              style: TextStyle(fontSize: 10, color: widget.textColor.withValues(alpha: 0.7))),
        ],
      ),
    );
  }
}

// ── Document ──────────────────────────────────────────────────────────────────

class _DocumentMedia extends StatelessWidget {
  const _DocumentMedia({
    required this.base64Data,
    required this.filename,
    required this.mimetype,
    required this.sizeBytes,
    required this.textColor,
  });
  final String base64Data;
  final String? filename;
  final String mimetype;
  final Object? sizeBytes;
  final Color textColor;

  Future<void> _share() async {
    try {
      final ext = filename != null && filename!.contains('.') ? filename!.split('.').last : _extFromMimetype(mimetype);
      final file = await _writeTempFile(base64Data, ext);
      await Share.shareXFiles([XFile(file.path)], text: filename ?? 'Document');
    } catch (_) {
      // Best-effort — nothing sensible to surface from a bare document tap failing.
    }
  }

  String _fmtSize(Object? bytes) {
    final b = num.tryParse('$bytes') ?? 0;
    if (b >= 1e6) return '${(b / 1e6).toStringAsFixed(1)} MB';
    if (b >= 1e3) return '${(b / 1e3).toStringAsFixed(0)} KB';
    return '$b B';
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: _share,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(10),
        constraints: const BoxConstraints(minWidth: 180),
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(8)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.insert_drive_file_rounded, color: textColor.withValues(alpha: 0.8)),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(filename ?? 'Document',
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w600)),
                  if (sizeBytes != null)
                    Text(_fmtSize(sizeBytes), style: TextStyle(color: textColor.withValues(alpha: 0.6), fontSize: 11)),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.ios_share_rounded, size: 18, color: textColor.withValues(alpha: 0.7)),
          ],
        ),
      ),
    );
  }
}
