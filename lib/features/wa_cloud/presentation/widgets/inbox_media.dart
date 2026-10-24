import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Real photo / voice note / video / file of a WA Cloud inbox message (`content.media`), drawn
/// the way WhatsApp does instead of a "[image]" placeholder.
class InboxMedia extends StatelessWidget {
  const InboxMedia({super.key, required this.type, required this.media, required this.textColor});

  final String type;
  final Map media;
  final Color textColor;

  String get _url => '${media['url'] ?? ''}';

  @override
  Widget build(BuildContext context) {
    switch (type) {
      case 'image':
      case 'sticker':
        return _image(context);
      case 'audio':
        return _AudioBubble(url: _url, voice: media['voice'] == true, color: textColor);
      case 'video':
        return _video(context);
      default:
        return _document(context);
    }
  }

  Widget _image(BuildContext context) {
    final sticker = type == 'sticker';
    return GestureDetector(
      onTap: () => showDialog(
        context: context,
        builder: (_) => Dialog.fullscreen(
          backgroundColor: Colors.black,
          child: Stack(children: [
            Center(child: InteractiveViewer(child: CachedNetworkImage(imageUrl: _url, fit: BoxFit.contain))),
            Positioned(
              top: 32,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ]),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(sticker ? 0 : 8),
        child: CachedNetworkImage(
          imageUrl: _url,
          width: sticker ? 130 : 220,
          height: sticker ? 130 : null,
          fit: sticker ? BoxFit.contain : BoxFit.cover,
          placeholder: (_, __) => const SizedBox(width: 220, height: 160, child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
          errorWidget: (_, __, ___) => _fallback(Icons.broken_image_rounded, 'Photo unavailable'),
        ),
      ),
    );
  }

  Widget _video(BuildContext context) => InkWell(
        onTap: () => launchUrl(Uri.parse(_url), mode: LaunchMode.externalApplication),
        child: Container(
          width: 220,
          height: 140,
          decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(8)),
          child: const Center(child: Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 52)),
        ),
      );

  Widget _document(BuildContext context) {
    final name = '${media['filename'] ?? 'Document'}';
    final mime = '${media['mime'] ?? ''}'.split('/').last.toUpperCase();
    final size = _size(media['size']);
    return InkWell(
      onTap: () => launchUrl(Uri.parse(_url), mode: LaunchMode.externalApplication),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: textColor.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(8)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(mime == 'PDF' ? Icons.picture_as_pdf_rounded : Icons.insert_drive_file_rounded, size: 30, color: textColor),
          const SizedBox(width: 10),
          Flexible(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w600, color: textColor)),
              Text([mime, size].where((e) => e.isNotEmpty).join(' · '),
                  style: TextStyle(fontSize: 11, color: textColor.withValues(alpha: 0.6))),
            ]),
          ),
          const SizedBox(width: 6),
          Icon(Icons.download_rounded, size: 20, color: textColor.withValues(alpha: 0.7)),
        ]),
      ),
    );
  }

  Widget _fallback(IconData icon, String label) => Padding(
        padding: const EdgeInsets.all(8),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 16, color: textColor.withValues(alpha: 0.6)),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontStyle: FontStyle.italic, color: textColor.withValues(alpha: 0.6))),
        ]),
      );

  static String _size(Object? v) {
    final n = num.tryParse('${v ?? ''}');
    if (n == null || n <= 0) return '';
    if (n < 1024) return '$n B';
    if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(0)} KB';
    return '${(n / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}

class _AudioBubble extends StatefulWidget {
  const _AudioBubble({required this.url, required this.voice, required this.color});
  final String url;
  final bool voice;
  final Color color;
  @override
  State<_AudioBubble> createState() => _AudioBubbleState();
}

class _AudioBubbleState extends State<_AudioBubble> {
  final _player = AudioPlayer();
  final _subs = <StreamSubscription>[];
  bool _playing = false;
  Duration _pos = Duration.zero;
  Duration _dur = Duration.zero;

  @override
  void initState() {
    super.initState();
    _subs.addAll([
      _player.onPlayerStateChanged.listen((s) => mounted ? setState(() => _playing = s == PlayerState.playing) : null),
      _player.onPositionChanged.listen((p) => mounted ? setState(() => _pos = p) : null),
      _player.onDurationChanged.listen((d) => mounted ? setState(() => _dur = d) : null),
      _player.onPlayerComplete.listen((_) => mounted ? setState(() { _playing = false; _pos = Duration.zero; }) : null),
    ]);
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_playing) {
      await _player.pause();
    } else {
      await _player.play(UrlSource(widget.url));
    }
  }

  String _fmt(Duration d) => '${d.inMinutes}:${d.inSeconds.remainder(60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final total = _dur.inMilliseconds;
    final progress = total > 0 ? (_pos.inMilliseconds / total).clamp(0.0, 1.0) : 0.0;
    return SizedBox(
      width: 230,
      child: Row(children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: Icon(_playing ? Icons.pause_rounded : Icons.play_arrow_rounded, color: widget.color, size: 30),
          onPressed: _toggle,
        ),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            LinearProgressIndicator(value: progress, minHeight: 3, color: widget.color, backgroundColor: widget.color.withValues(alpha: 0.2)),
            const SizedBox(height: 4),
            Text(_dur == Duration.zero ? (widget.voice ? 'Voice message' : 'Audio') : _fmt(_playing || _pos > Duration.zero ? _pos : _dur),
                style: TextStyle(fontSize: 11, color: widget.color.withValues(alpha: 0.7))),
          ]),
        ),
        if (widget.voice) Icon(Icons.mic_rounded, size: 18, color: widget.color.withValues(alpha: 0.7)),
      ]),
    );
  }
}
