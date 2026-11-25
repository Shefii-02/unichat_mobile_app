import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:unichat_mobile_app/core/network/api.dart';
import 'package:unichat_mobile_app/services/notification_tones.dart';

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
  /// This phone's push token (null until registered) — lets Settings tell which of your devices is this one.
  String? get token => _token;
  bool _listening = false;

  /// The team chat that is open on screen right now (its own messages should not beep at you).
  int? openChatId;

  // Tap on a team-chat push (message or @mention) → open that chat. The shell registers the handler once
  // it has a router context; a tap that arrives earlier (cold start) is held until then.
  void Function(int chatId, int? messageId)? _openChat;
  int? _pendingChat;
  int? _pendingMessage;
  set onOpenTeamChat(void Function(int chatId, int? messageId)? h) {
    _openChat = h;
    if (h != null && _pendingChat != null) {
      final id = _pendingChat!, mid = _pendingMessage;
      _pendingChat = null;
      _pendingMessage = null;
      _afterBuild(() => h(id, mid));
    }
  }

  // Lead pushes: an AI-handoff offer or a lead offer (shown as the Yes / No card, in the app or from a tap) and "a lead was assigned"
  // (opens the lead). Handlers are registered by the shell; one that arrives before that (cold start) is held.
  void Function(Map<String, dynamic> data)? _offer;
  void Function(int leadId)? _openLead;
  Map<String, dynamic>? _pendingOffer;
  int? _pendingLead;
  set onLeadOffer(void Function(Map<String, dynamic> data)? h) {
    _offer = h;
    if (h != null && _pendingOffer != null) { final d = _pendingOffer!; _pendingOffer = null; _afterBuild(() => h(d)); }
  }

  set onOpenLead(void Function(int leadId)? h) {
    _openLead = h;
    if (h != null && _pendingLead != null) { final id = _pendingLead!; _pendingLead = null; _afterBuild(() => h(id)); }
  }

  // Any other tap (wallet, campaign, WhatsApp session, a test push …) opens its screen — or the Notifications list — instead of doing nothing.
  void Function(String route)? _openRoute;
  String? _pendingRoute;
  set onOpenRoute(void Function(String route)? h) {
    _openRoute = h;
    if (h != null && _pendingRoute != null) { final r = _pendingRoute!; _pendingRoute = null; _afterBuild(() => h(r)); }
  }

  /// The handlers are assigned while the shell is BUILDING — navigating then throws, so a held tap is delivered right after the frame.
  void _afterBuild(VoidCallback f) {
    WidgetsBinding.instance.addPostFrameCallback((_) => f());
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  static const _routeFor = <String, String>{
    'open_leads': '/leads',
    'open_wallet': '/wallet',
    'open_campaign': '/campaigns',
    'open_wa_session': '/wa-chat/sessions',
    'open_team_chat_reports': '/team-chat/admin',
  };

  void _goRoute(String route) {
    if (_openRoute != null) {
      _openRoute!(route);
    } else {
      _pendingRoute = route;
    }
  }

  /// true when the message was one of the lead pushes (and has been handled)
  bool _handleLead(RemoteMessage m) {
    final action = '${m.data['action']}';
    if (action == 'ai_handoff_offer' || action == 'lead_offer') {
      final d = Map<String, dynamic>.from(m.data);
      _offer != null ? _offer!(d) : _pendingOffer = d;
      return true;
    }
    if (action == 'open_lead') {
      final id = int.tryParse('${m.data['lead_id']}');
      if (id != null) { _openLead != null ? _openLead!(id) : _pendingLead = id; }
      return true;
    }
    return false;
  }

  void _handleTap(RemoteMessage m) {
    if (_handleLead(m)) return;
    if (m.data['action'] == 'open_widget_chat') {
      final cid = int.tryParse('${m.data['widget_conversation_id']}');
      _goRoute(cid != null ? '/wa-agent/widget-chats?c=$cid' : '/wa-agent/widget-chats');
      return;
    }
    if (m.data['action'] != 'open_team_chat') {
      _goRoute(_routeFor['${m.data['action']}'] ?? '/notifications');   // never a dead tap
      return;
    }
    final id = int.tryParse('${m.data['chat_id']}');
    if (id == null) {
      _goRoute('/team-chat');
      return;
    }
    // an @mention opens the chat right at that message; a plain message just opens the chat
    final mid = m.data['type'] == 'team_chat_mention' ? int.tryParse('${m.data['message_id']}') : null;
    if (_openChat != null) {
      _openChat!(id, mid);
    } else {
      _pendingChat = id;
      _pendingMessage = mid;
    }
  }

  Future<void> register() async {
    try {
      final fm = FirebaseMessaging.instance;
      final settings = await fm.requestPermission(alert: true, badge: true, sound: true);
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;
      NotificationTones.ensureChannels();   // Android: one channel per tone, so a closed app plays the right sound

      // Tap handling comes FIRST: it must work even if the token step below fails (no network, APNs not ready …).
      if (!_listening) {
        _listening = true;
        FirebaseMessaging.onMessageOpenedApp.listen(_handleTap);
        // the app is open: show the offer card straight away (Android shows no banner for a foreground push)
        FirebaseMessaging.onMessage.listen((m) {
          final a = '${m.data['action']}';
          // the sound the backend chose for this kind of notification (skipped for the chat you are looking at)
          final inOpenChat = a == 'open_team_chat' && int.tryParse('${m.data['chat_id']}') == openChatId;
          if (!inOpenChat) NotificationTones.play(m.data['tone'] as String?);
          if (a == 'ai_handoff_offer' || a == 'lead_offer') _handleLead(m);
        });
        // the app was closed and the user tapped the notification to start it
        final initial = await fm.getInitialMessage();
        if (initial != null) _handleTap(initial);
      }

      // iOS needs the APNs token before an FCM token can be issued.
      if (Platform.isIOS) {
        await fm.setForegroundNotificationPresentationOptions(alert: true, badge: true, sound: false);   // the app plays the backend's tone itself
        await fm.getAPNSToken();
      }

      final token = await fm.getToken();
      if (token != null) await _send(token);
      fm.onTokenRefresh.listen(_send);
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
