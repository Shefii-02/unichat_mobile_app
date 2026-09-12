import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';
import 'package:unichat_mobile_app/core/network/dio_client.dart'
    show DioClient, isAuthFailure;
import 'package:unichat_mobile_app/core/storage/secure_storage.dart';
import 'package:unichat_mobile_app/core/storage/local_storage.dart';
import 'package:unichat_mobile_app/core/permissions/permission_guard.dart';
import 'models/user_model.dart';

/// Result of `POST /device-auth/check` — enough to render the confirm screen.
class DeviceCheckResult {
  const DeviceCheckResult({
    required this.name,
    required this.email,
    required this.expiresAt,
  });

  final String name;
  final String? email;
  final DateTime expiresAt;

  Duration get remaining {
    final d = expiresAt.difference(DateTime.now());
    return d.isNegative ? Duration.zero : d;
  }
}

/// A linked device returned inside a 409 `device_limit` payload.
class LinkedDevice {
  const LinkedDevice({
    required this.id,
    required this.name,
    required this.platform,
    this.lastActiveAt,
  });

  final int id;
  final String name;
  final String? platform;
  final DateTime? lastActiveAt;

  factory LinkedDevice.fromJson(Map<String, dynamic> j) => LinkedDevice(
        id: j['id'] as int,
        name: j['device_name'] as String? ?? 'Device',
        platform: j['platform'] as String?,
        lastActiveAt: j['last_active_at'] != null
            ? DateTime.tryParse(j['last_active_at'] as String)
            : null,
      );
}

/// Thrown when the account is already at its device limit. Carries the list of
/// devices and the credential to retry the claim with once one is removed.
class DeviceLimitException implements Exception {
  DeviceLimitException({
    required this.message,
    required this.max,
    required this.devices,
    this.retryToken,
    this.retryPin,
  });

  final String message;
  final int max;
  final List<LinkedDevice> devices;
  final String? retryToken;
  final String? retryPin;
}

/// Thrown when the challenge is invalid / expired — surfaced to the user as
/// "refresh the code on the web".
class DeviceChallengeException implements Exception {
  DeviceChallengeException(this.message);
  final String message;
  @override
  String toString() => message;
}

class DeviceAuthRepository {
  final Dio _dio = DioClient.laravelDio;
  static const _uuid = Uuid();

  /// A stable per-install id. Generated once and kept in local storage.
  Future<String> deviceUid() async {
    var uid = LocalStorage.getString(LocalStorage.kDeviceUid);
    if (uid == null || uid.isEmpty) {
      uid = _uuid.v4();
      await LocalStorage.setString(LocalStorage.kDeviceUid, uid);
    }
    return uid;
  }

  Future<String> _deviceName() async {
    final cached = LocalStorage.getString(LocalStorage.kDeviceName);
    if (cached != null && cached.isNotEmpty) return cached;
    String name;
    if (Platform.isIOS) {
      name = 'iPhone';
    } else if (Platform.isAndroid) {
      name = 'Android phone';
    } else {
      name = 'Mobile device';
    }
    await LocalStorage.setString(LocalStorage.kDeviceName, name);
    return name;
  }

  String get _platform {
    if (Platform.isIOS) return 'ios';
    if (Platform.isAndroid) return 'android';
    return 'other';
  }

  Map<String, dynamic> _credential({String? token, String? pin}) {
    if (token != null && token.isNotEmpty) return {'token': token};
    if (pin != null && pin.isNotEmpty) return {'pin': pin};
    throw DeviceChallengeException('Provide a QR code or a PIN.');
  }

  /// Decode the QR payload `{ "v": 1, "t": "<40-char token>" }`.
  /// Accepts either the JSON payload or a bare 40-char token.
  static String? tokenFromQr(String raw) {
    final decoded = raw.trim();
    if (decoded.startsWith('{')) {
      try {
        final map = jsonDecode(decoded);
        final t = map is Map ? map['t'] : null;
        if (t is String && t.length == 40) return t;
      } catch (_) {}
      return null;
    }
    return decoded.length == 40 ? decoded : null;
  }

  DeviceChallengeException _asChallengeError(DioException e) {
    final data = e.response?.data;
    if (data is Map) {
      final errors = data['errors'];
      if (errors is Map && errors.isNotEmpty) {
        final first = errors.values.first;
        if (first is List && first.isNotEmpty) {
          return DeviceChallengeException(first.first.toString());
        }
      }
      if (data['message'] is String) {
        return DeviceChallengeException(data['message'] as String);
      }
    }
    return DeviceChallengeException('Could not verify that code. Try again.');
  }

  Future<DeviceCheckResult> check({String? token, String? pin}) async {
    try {
      final res = await _dio.post('/device-auth/check',
          data: _credential(token: token, pin: pin));
      final body = res.data as Map<String, dynamic>;
      final user = body['user'] as Map<String, dynamic>? ?? const {};
      return DeviceCheckResult(
        name: user['name'] as String? ?? 'this account',
        email: user['email'] as String?,
        expiresAt: DateTime.tryParse(body['expires_at'] as String? ?? '') ??
            DateTime.now().add(const Duration(seconds: 45)),
      );
    } on DioException catch (e) {
      throw _asChallengeError(e);
    }
  }

  /// Links this device and logs in. On success the JWT + user are persisted and
  /// the resolved [UserModel] is returned.
  Future<UserModel> claim({String? token, String? pin}) async {
    final uid = await deviceUid();
    final payload = <String, dynamic>{
      ..._credential(token: token, pin: pin),
      'device_uid': uid,
      'device_name': await _deviceName(),
      'platform': _platform,
      'app_version': '1.0.0',
      if (LocalStorage.getString(LocalStorage.kPushToken) != null)
        'push_token': LocalStorage.getString(LocalStorage.kPushToken),
    };

    try {
      final res = await _dio.post('/device-auth/claim', data: payload);
      return _persistSession(res.data as Map<String, dynamic>);
    } on DioException catch (e) {
      if (e.response?.statusCode == 409 &&
          (e.response?.data is Map) &&
          (e.response!.data as Map)['error'] == 'device_limit') {
        final d = e.response!.data as Map<String, dynamic>;
        final retry = (d['retry_with'] as Map?) ?? const {};
        throw DeviceLimitException(
          message: d['message'] as String? ?? 'Device limit reached.',
          max: d['max'] as int? ?? 2,
          devices: ((d['devices'] as List?) ?? const [])
              .map((e) => LinkedDevice.fromJson(e as Map<String, dynamic>))
              .toList(),
          retryToken: retry['token'] as String?,
          retryPin: retry['pin'] as String?,
        );
      }
      throw _asChallengeError(e);
    }
  }

  /// Removes a linked device to free a slot, then the caller retries [claim].
  Future<void> removeDevice({
    required int deviceId,
    String? token,
    String? pin,
  }) async {
    try {
      await _dio.post('/device-auth/remove-device', data: {
        'device_id': deviceId,
        ..._credential(token: token, pin: pin),
      });
    } on DioException catch (e) {
      throw _asChallengeError(e);
    }
  }

  Future<UserModel> _persistSession(Map<String, dynamic> body) async {
    final token = body['access_token'] as String;
    await SecureStorageService.saveToken(token);

    final userMap = body['user'] as Map<String, dynamic>;
    final user = UserModel.fromJson(userMap);
    await LocalStorage.setJson(LocalStorage.kUser, user.toJson());
    PermissionGuard.setPermissions(user.permissions, user.role);

    final device = body['device'] as Map<String, dynamic>?;
    if (device != null) {
      await LocalStorage.setString(
          LocalStorage.kDeviceUid, device['device_uid'] as String);
      if (device['device_name'] != null) {
        await LocalStorage.setString(
            LocalStorage.kDeviceName, device['device_name'] as String);
      }
    }
    return user;
  }

  /// Called on cold start — confirms the device is still authorised.
  Future<bool> statusOk() async {
    try {
      final res = await _dio.get('/device-auth/status');
      final body = res.data as Map<String, dynamic>;
      return body['valid'] == true;
    } on DioException catch (e) {
      // An expired / revoked token (401, 419, or the backend's buggy 500)
      // has already been cleared by the interceptor — sign the user out.
      if (isAuthFailure(e.response)) return false;
      return true; // genuine network hiccup — don't sign the user out
    }
  }

  Future<void> heartbeat() async {
    try {
      await _dio.post('/device-auth/heartbeat', data: {
        'app_version': '1.0.0',
        if (LocalStorage.getString(LocalStorage.kPushToken) != null)
          'push_token': LocalStorage.getString(LocalStorage.kPushToken),
      });
    } catch (_) {/* best effort */}
  }

  Future<void> logout() async {
    try {
      await _dio.post('/device-auth/logout');
    } catch (_) {/* ignore */}
    await SecureStorageService.clearAll();
    final uid = LocalStorage.getString(LocalStorage.kDeviceUid);
    final name = LocalStorage.getString(LocalStorage.kDeviceName);
    await LocalStorage.remove(LocalStorage.kUser);
    // keep device_uid + name so re-linking is a known device
    if (uid != null) await LocalStorage.setString(LocalStorage.kDeviceUid, uid);
    if (name != null) await LocalStorage.setString(LocalStorage.kDeviceName, name);
    PermissionGuard.clear();
  }
}
