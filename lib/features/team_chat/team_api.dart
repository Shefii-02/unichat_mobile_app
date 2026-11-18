import 'dart:async';

import 'package:dio/dio.dart';
import 'package:unichat_mobile_app/core/network/api.dart';
import 'package:unichat_mobile_app/core/network/dio_client.dart';
import 'package:unichat_mobile_app/core/socket/socket_service.dart';

/// Team chat REST. The chat server (same host as the live socket, `ApiConstants.chatBase`) serves it first — the fetch
/// (chats, chat info, messages, users), JSON send and read / delivered receipts — and Laravel is only the fallback when
/// Node is unreachable, errors (5xx), isn't deployed yet (404) or rejects the token (401). Same paths and JSON shapes on
/// both, so callers don't care which one answered. File uploads and group admin always go to Laravel (`Api`).
class TeamApi {
  TeamApi._();

  static bool _fallbackWorthy(DioException e) {
    final c = e.response?.statusCode;
    return c == null || c >= 500 || c == 404 || c == 401;
  }

  /// When Node last failed in a fallback-worthy way. While it is recent we go straight to Laravel instead of making every
  /// request wait out Node's connect timeout (a Cloudflare 522 takes ~20s) before falling back.
  static DateTime? _nodeDownAt;
  static const _nodeCooldown = Duration(minutes: 2);
  static const _nodeAttemptTimeout = Duration(seconds: 6);

  /// The live socket is served by the same Node host as this REST API, so a socket that is not connected means Node is
  /// most likely unreachable too — don't make a burst of parallel requests each wait out the timeout to find that out.
  static bool get _nodeCoolingDown {
    if (!SocketService().isConnected) return true;
    final at = _nodeDownAt;
    return at != null && DateTime.now().difference(at) < _nodeCooldown;
  }

  static Future<Response<dynamic>> _call(
    Future<Response<dynamic>> Function(Dio dio, String prefix) run,
  ) async {
    if (!_nodeCoolingDown) {
      try {
        final res = await run(DioClient.chatDio, '/api').timeout(_nodeAttemptTimeout);
        _nodeDownAt = null;
        return res;
      } on TimeoutException {
        _nodeDownAt = DateTime.now();
      } on DioException catch (e) {
        if (!_fallbackWorthy(e)) rethrow;
        _nodeDownAt = DateTime.now();
      }
    }
    return await run(DioClient.laravelDio, '');
  }

  static Map<String, dynamic> _map(dynamic d) {
    if (d is Map) {
      final inner = d['data'];
      // Laravel / Node wrap single objects in `data` only for lists; objects come back bare.
      return Map<String, dynamic>.from(inner is Map && d.length == 1 ? inner : d);
    }
    return <String, dynamic>{};
  }

  static List<Map<String, dynamic>> _list(dynamic d) {
    final raw = d is Map ? d['data'] : d;
    return (raw is List ? raw : const []).whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
  }

  /// GET → list under `data`.
  static Future<List<Map<String, dynamic>>> list(String path, {Map<String, dynamic>? query}) async =>
      _list((await _call((d, p) => d.get('$p$path', queryParameters: query))).data);

  /// GET → one object.
  static Future<Map<String, dynamic>> one(String path, {Map<String, dynamic>? query}) async =>
      _map((await _call((d, p) => d.get('$p$path', queryParameters: query))).data);

  /// GET → the whole body (when the response carries paging meta next to `data`).
  static Future<Map<String, dynamic>> page(String path, {Map<String, dynamic>? query}) async {
    final d = (await _call((dio, p) => dio.get('$p$path', queryParameters: query))).data;
    return d is Map ? Map<String, dynamic>.from(d) : <String, dynamic>{};
  }

  static Future<Map<String, dynamic>> post(String path, {Object? data}) async =>
      _map((await _call((d, p) => d.post('$p$path', data: data))).data);

  static String error(Object e) => apiErrorMessage(e);
}
