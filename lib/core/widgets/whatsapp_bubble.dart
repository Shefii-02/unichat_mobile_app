import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../utils/format_utils.dart';

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
            Text(body, style: TextStyle(color: textColor, fontSize: 14.5)),
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
}
