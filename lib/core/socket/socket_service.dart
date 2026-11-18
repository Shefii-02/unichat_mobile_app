import 'dart:async';
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../constants/api_constants.dart';

class SocketService {
  static final SocketService _instance = SocketService._();
  factory SocketService() => _instance;
  SocketService._();

  io.Socket? _socket;
  int? _staffId;

  final _leadNotifCtrl    = StreamController<Map<String, dynamic>>.broadcast();
  final _aiOfferCtrl      = StreamController<Map<String, dynamic>>.broadcast();
  final _messageCtrl      = StreamController<Map<String, dynamic>>.broadcast();
  final _assignmentCtrl   = StreamController<Map<String, dynamic>>.broadcast();
  final _slaCtrl          = StreamController<Map<String, dynamic>>.broadcast();
  final _connectCtrl      = StreamController<bool>.broadcast();
  final _widgetChatCtrl   = StreamController<Map<String, dynamic>>.broadcast();
  final _teamChatCtrl     = StreamController<Map<String, dynamic>>.broadcast();
  final _teamTypingCtrl   = StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get leadNotifications => _leadNotifCtrl.stream;
  Stream<Map<String, dynamic>> get aiHandoffOffers   => _aiOfferCtrl.stream;
  Stream<Map<String, dynamic>> get newMessages       => _messageCtrl.stream;
  Stream<Map<String, dynamic>> get assignmentUpdates => _assignmentCtrl.stream;
  Stream<Map<String, dynamic>> get slaAlerts         => _slaCtrl.stream;
  Stream<bool>                 get connectionState   => _connectCtrl.stream;
  /// Website-chat changes pushed by chat-server: {conversation_id, kind, message?}.
  Stream<Map<String, dynamic>> get widgetChatUpdates => _widgetChatCtrl.stream;

  /// Team chat changes: {chat_id, kind: message|edit|delete|reaction|read|system, message_id?, by}.
  Stream<Map<String, dynamic>> get teamChatEvents => _teamChatCtrl.stream;
  /// {chat_id, user_id, name, typing}
  Stream<Map<String, dynamic>> get teamTyping => _teamTypingCtrl.stream;

  /// Tell the other members of [chatId] that this user is (or stopped) typing.
  void emitTeamTyping(int chatId, bool typing) =>
      _socket?.emit('team_typing', {'chat_id': chatId, 'typing': typing});

  /// Sends a command over the socket and waits for the server's ack. Returns `null` when the socket is
  /// down or the server doesn't answer within [timeout], so callers can fall back to REST.
  Future<Map<String, dynamic>?> call(String event, Map<String, dynamic> data,
      {Duration timeout = const Duration(seconds: 8)}) {
    final s = _socket;
    if (s == null || !s.connected) return Future.value(null);
    final c = Completer<Map<String, dynamic>?>();
    final timer = Timer(timeout, () { if (!c.isCompleted) c.complete(null); });
    s.emitWithAck(event, data, ack: (res) {
      timer.cancel();
      if (!c.isCompleted) c.complete(res is Map ? _toMap(res) : null);
    });
    return c.future;
  }

  bool get isConnected => _socket?.connected ?? false;

  void connect(String token, int staffId, int companyId) {
    if (_socket != null && _staffId == staffId) return; // already connected / connecting
    _socket?.dispose();
    _staffId = staffId;
    _socket = io.io(
      // The Node gateway lives on the /staff namespace (the default namespace has no handlers).
      '${ApiConstants.chatSocketUrl}/staff',
      io.OptionBuilder()
        .setTransports(['websocket'])
        .enableAutoConnect()
        .enableReconnection()
        .setReconnectionAttempts(999)
        .setReconnectionDelay(2000)
        .setAuth({'token': token})
        .build(),
    );

    _socket!.onConnect((_) {
      _connectCtrl.add(true);
      _socket!.emit('staff_online', {'staff_id': staffId, 'company_id': companyId});
    });

    _socket!.onDisconnect((_) => _connectCtrl.add(false));

    _socket!.onReconnect((_) {
      _socket!.emit('staff_online', {'staff_id': staffId, 'company_id': companyId});
    });

    _socket!.on('new_lead_notification', (d) => _leadNotifCtrl.add(_toMap(d)));
    _socket!.on('ai_handoff_offer',       (d) => _aiOfferCtrl.add(_toMap(d)));
    _socket!.on('new_message',             (d) => _messageCtrl.add(_toMap(d)));
    _socket!.on('lead_assignment_update',  (d) => _assignmentCtrl.add(_toMap(d)));
    _socket!.on('sla_breach',              (d) => _slaCtrl.add(_toMap(d)));
    _socket!.on('widget_chat_update',      (d) => _widgetChatCtrl.add(_toMap(d)));
    _socket!.on('team_chat',               (d) => _teamChatCtrl.add(_toMap(d)));
    _socket!.on('team_typing',             (d) => _teamTypingCtrl.add(_toMap(d)));
  }

  void disconnect() {
    if (_staffId != null) {
      _socket?.emit('staff_offline', {'staff_id': _staffId});
    }
    _socket?.disconnect();
    _socket = null;
  }

  Map<String, dynamic> _toMap(dynamic d) {
    if (d is Map<String, dynamic>) return d;
    if (d is Map) return Map<String, dynamic>.from(d);
    return {};
  }
}
