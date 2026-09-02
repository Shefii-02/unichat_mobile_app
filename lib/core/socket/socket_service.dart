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

  Stream<Map<String, dynamic>> get leadNotifications => _leadNotifCtrl.stream;
  Stream<Map<String, dynamic>> get aiHandoffOffers   => _aiOfferCtrl.stream;
  Stream<Map<String, dynamic>> get newMessages       => _messageCtrl.stream;
  Stream<Map<String, dynamic>> get assignmentUpdates => _assignmentCtrl.stream;
  Stream<Map<String, dynamic>> get slaAlerts         => _slaCtrl.stream;
  Stream<bool>                 get connectionState   => _connectCtrl.stream;

  bool get isConnected => _socket?.connected ?? false;

  void connect(String token, int staffId, int companyId) {
    _staffId = staffId;
    _socket = io.io(
      ApiConstants.socketUrl,
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
