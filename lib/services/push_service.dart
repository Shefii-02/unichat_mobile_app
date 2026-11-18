import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:unichat_mobile_app/core/network/api.dart';

/// Background/terminated FCM handler — the OS shows the `notification` payload itself,
/// this only needs Firebase initialised in the background isolate.
@pragma('vm:entry-point')
Future<void> firebaseBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

/// Registers this device's FCM token with the backend (`/push/register-token`) once a
/// user is signed in, keeps it fresh on rotation, and deactivates it on sign-out.
class PushService {
  PushService._();
  static final PushService instance = PushService._();

  String? _token;
  bool _listening = false;

  // Tap on a team-chat push (message or @mention) → open that chat. The shell registers the handler once
  // it has a router context; a tap that arrives earlier (cold start) is held until then.
  void Function(int chatId)? _openChat;
  int? _pendingChat;
  set onOpenTeamChat(void Function(int chatId)? h) {
    _openChat = h;
    if (h != null && _pendingChat != null) {
      final id = _pendingChat!;
      _pendingChat = null;
      h(id);
    }
  }

  void _handleTap(RemoteMessage m) {
    if (m.data['action'] != 'open_team_chat') return;
    final id = int.tryParse('${m.data['chat_id']}');
    if (id == null) return;
    if (_openChat != null) {
      _openChat!(id);
    } else {
      _pendingChat = id;
    }
  }

  Future<void> register() async {
    try {
      final fm = FirebaseMessaging.instance;
      final settings = await fm.requestPermission(alert: true, badge: true, sound: true);
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;

      // iOS needs the APNs token before an FCM token can be issued.
      if (Platform.isIOS) {
        await fm.setForegroundNotificationPresentationOptions(alert: true, badge: true, sound: true);
        await fm.getAPNSToken();
      }

      final token = await fm.getToken();
      if (token != null) await _send(token);

      if (!_listening) {
        _listening = true;
        fm.onTokenRefresh.listen(_send);
        FirebaseMessaging.onMessageOpenedApp.listen(_handleTap);
        final initial = await fm.getInitialMessage();
        if (initial != null) _handleTap(initial);
      }
    } catch (e) {
      debugPrint('Push register failed: $e');
    }
  }

  Future<void> _send(String token) async {
    _token = token;
    await Api.post('/push/register-token', data: {
      'fcm_token': token,
      'device_type': Platform.isIOS ? 'ios' : 'android',
    });
  }

  /// Call before the auth token is cleared.
  Future<void> unregister() async {
    final token = _token;
    if (token == null) return;
    try {
      await Api.raw.delete('/push/unregister-token', data: {'fcm_token': token});
    } catch (_) {}
    _token = null;
  }
}
