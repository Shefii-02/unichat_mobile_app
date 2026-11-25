import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Notification sounds. The backend decides the sound for each notification and sends its key (`tone`) in the push; the same four
/// files are bundled here (assets/sounds, and res/raw for Android's notification channels) so they play instantly.
///   • app open     → [play] the bundled file
///   • app closed   → Android uses the channel named `tone_<key>` (created by [ensureChannels]) whose sound is that file
class NotificationTones {
  NotificationTones._();

  /// key → file name (same files as backend/public/tones)
  static const files = <String, String>{
    'lead_popup': 'lead_popup_notifications.mp3',
    'lead': 'lead_notifications.mp3',
    'conversation': 'conversation_tone.mp3',
    'general': 'general_notifications.mp3',
  };
  static const _labels = <String, String>{
    'lead_popup': 'Lead offers',
    'lead': 'Lead activity',
    'conversation': 'Conversations & chat',
    'general': 'General',
  };

  static final AudioPlayer _player = AudioPlayer()..setPlayerMode(PlayerMode.lowLatency);
  static final Map<String, DateTime> _last = {};

  /// Plays a tone once; the same tone within a second is ignored (a burst of pushes is one sound).
  static Future<void> play(String? key) async {
    if (key != null && key.isEmpty) return;   // a notification-only push carries an empty tone
    final file = files[key ?? 'general'] ?? files['general']!;
    final now = DateTime.now();
    final last = _last[file];
    if (last != null && now.difference(last).inMilliseconds < 1000) return;
    _last[file] = now;
    try {
      await _player.stop();
      await _player.play(AssetSource('sounds/$file'));
    } catch (e) {
      debugPrint('Tone failed: $e');
    }
  }

  static bool _channelsDone = false;

  /// Android 8+: the sound belongs to the channel and can't change later — one channel per tone, each with its own file.
  static Future<void> ensureChannels() async {
    if (_channelsDone || !Platform.isAndroid) return;
    try {
      final plugin = FlutterLocalNotificationsPlugin();
      await plugin.initialize(const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')));
      final android = plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      for (final e in files.entries) {
        await android?.createNotificationChannel(AndroidNotificationChannel(
          'tone_${e.key}',
          _labels[e.key] ?? e.key,
          importance: Importance.high,
          sound: RawResourceAndroidNotificationSound(e.value.replaceAll('.mp3', '')),
          playSound: true,
        ));
      }
      // "notification only": shown, but no sound
      await android?.createNotificationChannel(const AndroidNotificationChannel('tone_silent', 'Notification only (no tone)', importance: Importance.defaultImportance, playSound: false));
      _channelsDone = true;
    } catch (e) {
      debugPrint('Tone channels failed: $e');
    }
  }
}
