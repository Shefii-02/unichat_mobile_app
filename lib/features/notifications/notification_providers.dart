import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:unichat_mobile_app/core/network/api.dart';

/// The bell's number: this person's unread notifications plus unread team-chat messages. Re-read whenever the provider is invalidated
/// (the Notifications screen does that after reading, the shell on resume).
final notificationBadgeProvider = FutureProvider.autoDispose<int>((ref) async {
  try {
    final d = await Api.one('/notifications/unread-count');
    return (d['badge'] as num?)?.toInt() ?? 0;
  } catch (_) {
    return 0;
  }
});
