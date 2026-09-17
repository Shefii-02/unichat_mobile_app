import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../constants/app_colors.dart';
import '../utils/format_utils.dart';
import 'chat_media_content.dart';

final _urlPattern = RegExp(r'((?:https?://|www\.)[^\s]+)', caseSensitive: false);

class WhatsAppBubble extends StatelessWidget {
  const WhatsAppBubble({
    super.key,
    required this.message,
    required this.isSent,
    this.isDark = false,
  });

  final Map<String, dynamic> message;
  final bool isSent;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final body = message['body'] as String? ?? message['text'] as String? ?? '';
    final ts   = message['timestamp'] != null
        ? DateTime.fromMillisecondsSinceEpoch(
            (message['timestamp'] as int) * 1000)
        : null;
    final status = message['ack'] as int? ?? 0;
    final type = message['type'] as String? ?? 'text';
    final metadata = message['metadata'] as Map<String, dynamic>?;
    final quoted = metadata?['quotedMessage'] as Map<String, dynamic>?;
    final location = type == 'location' ? (metadata?['location'] as Map<String, dynamic>?) : null;
    final call = type == 'call' ? (metadata?['call'] as Map<String, dynamic>?) : null;
    final media = metadata?['media'] as Map<String, dynamic>?;
    final isMedia = isMediaMessageType(type);

    final bg = isSent
        ? (isDark ? AppColors.darkBubbleSent : AppColors.bubbleSent)
        : (isDark ? AppColors.darkBubbleRcv  : AppColors.bubbleReceived);

    final textColor = isSent
        ? (isDark ? Colors.white : AppColors.textPrimary)
        : AppColors.textPrimary;

    return Align(
      alignment: isSent ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
        margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(12),
            topRight: const Radius.circular(12),
            bottomLeft: Radius.circular(isSent ? 12 : 0),
            bottomRight: Radius.circular(isSent ? 0 : 12),
          ),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 3, offset: const Offset(0, 1))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (quoted != null) _quotedPreview(quoted, textColor),
            if (type == 'revoked')
              Text('This message was deleted',
                  style: TextStyle(color: textColor.withValues(alpha: 0.6), fontSize: 13.5, fontStyle: FontStyle.italic))
            else if (type == 'call')
              _callEvent(call, textColor)
            else if (location != null) ...[
              _locationCard(location, textColor),
            ] else if (isMedia) ...[
              buildMediaContent(type, media, textColor),
              if (body.isNotEmpty) ...[
                const SizedBox(height: 6),
                _linkifiedText(body, textColor),
              ],
            ] else
              _linkifiedText(body, textColor),
            const SizedBox(height: 2),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  FormatUtils.time(ts),
                  style: const TextStyle(color: AppColors.textLight, fontSize: 11),
                ),
                if (isSent) ...[
                  const SizedBox(width: 3),
                  Icon(
                    status >= 3 ? Icons.done_all : Icons.done,
                    size: 14,
                    color: status >= 3 ? AppColors.accent : AppColors.textLight,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _callEvent(Map<String, dynamic>? call, Color textColor) {
    final video = call?['video'] == true;
    final missed = call?['missed'] == true;
    final color = missed ? AppColors.error : textColor.withValues(alpha: 0.85);
    final label = missed
        ? (video ? 'Missed video call' : 'Missed voice call')
        : (video ? 'Video call' : 'Voice call');
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(video ? Icons.videocam_rounded : Icons.call_rounded, size: 16, color: color),
      const SizedBox(width: 6),
      Text(label, style: TextStyle(color: color, fontSize: 13.5)),
    ]);
  }

  /// Renders `text` with any `http(s)://` / `www.` URL as a tappable, underlined link — plain
  /// `Text` never made these clickable, so a shared link just sat there as inert text.
  Widget _linkifiedText(String text, Color textColor) {
    if (text.isEmpty) return const SizedBox.shrink();
    final matches = _urlPattern.allMatches(text);
    if (matches.isEmpty) return Text(text, style: TextStyle(color: textColor, fontSize: 14.5));

    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final m in matches) {
      if (m.start > cursor) spans.add(TextSpan(text: text.substring(cursor, m.start)));
      final url = m.group(0)!;
      final target = url.startsWith('http') ? url : 'https://$url';
      spans.add(TextSpan(
        text: url,
        style: const TextStyle(color: AppColors.accent, decoration: TextDecoration.underline),
        recognizer: TapGestureRecognizer()
          ..onTap = () => launchUrl(Uri.parse(target), mode: LaunchMode.externalApplication),
      ));
      cursor = m.end;
    }
    if (cursor < text.length) spans.add(TextSpan(text: text.substring(cursor)));

    return Text.rich(TextSpan(style: TextStyle(color: textColor, fontSize: 14.5), children: spans));
  }

  Widget _quotedPreview(Map<String, dynamic> quoted, Color textColor) {
    final quotedBody = quoted['body'] as String? ?? '';
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(6),
        border: Border(left: BorderSide(color: textColor.withValues(alpha: 0.5), width: 3)),
      ),
      child: Text(
        quotedBody.isEmpty ? 'Original message' : quotedBody,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: textColor.withValues(alpha: 0.75), fontSize: 12.5),
      ),
    );
  }

  Widget _locationCard(Map<String, dynamic> location, Color textColor) {
    final description = location['description'] as String?;
    final address = location['address'] as String?;
    final lat = location['latitude'];
    final lng = location['longitude'];
    final label = (description?.isNotEmpty ?? false)
        ? description!
        : (address?.isNotEmpty ?? false)
            ? address!
            : (lat != null && lng != null ? '$lat, $lng' : 'Location shared');
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.location_on_rounded, size: 18, color: textColor.withValues(alpha: 0.8)),
          const SizedBox(width: 6),
          Flexible(
            child: Text(label,
                maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: textColor, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
