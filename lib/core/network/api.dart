import 'package:dio/dio.dart';
import 'dio_client.dart';

/// Thin wrapper over the Laravel Dio client that normalises the API's response
/// envelopes. The backend variously returns:
///   { "data": [...] }              (resource collections)
///   { "data": { "data": [...] } }  (paginated collections)
///   { "data": {...} }              (single resources)
///   [...]  /  {...}                (bare)
class Api {
  Api._();
  static final Dio _dio = DioClient.laravelDio;

  static Dio get raw => _dio;

  /// GET returning a list. Digs through `data` / `data.data` / `items` wrappers.
  static Future<List<Map<String, dynamic>>> list(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    final res = await _dio.get(path, queryParameters: query);
    return _asList(res.data);
  }

  /// GET returning a single object (unwraps one level of `data`).
  static Future<Map<String, dynamic>> one(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    final res = await _dio.get(path, queryParameters: query);
    return _asMap(res.data);
  }

  static Future<Map<String, dynamic>> post(String path, {Object? data}) async {
    final res = await _dio.post(path, data: data);
    return _asMap(res.data);
  }

  static Future<Map<String, dynamic>> put(String path, {Object? data}) async {
    final res = await _dio.put(path, data: data);
    return _asMap(res.data);
  }

  static Future<Map<String, dynamic>> patch(String path, {Object? data}) async {
    final res = await _dio.patch(path, data: data);
    return _asMap(res.data);
  }

  static Future<void> delete(String path) => _dio.delete(path);

  // ── envelope helpers ────────────────────────────────────────────────
  static List<Map<String, dynamic>> _asList(dynamic body) {
    dynamic v = body;
    if (v is Map) {
      v = v['data'] ??
          v['items'] ??
          v['results'] ??
          v['records'] ??
          v['devices'] ??
          v['labels'] ??
          v['phone_numbers'] ??
          v['accounts'] ??
          v['automations'] ??
          v['builders'] ??
          v['forms'] ??
          v['roles'] ??
          v;
      if (v is Map && v['data'] is List) v = v['data'];
    }
    if (v is List) {
      return v
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList(growable: false);
    }
    return const [];
  }

  static Map<String, dynamic> _asMap(dynamic body) {
    dynamic v = body;
    if (v is Map && v['data'] is Map) v = v['data'];
    if (v is Map) return v.cast<String, dynamic>();
    return {'value': v};
  }
}

/// Human-readable message pulled out of a DioException.
String apiErrorMessage(Object e) {
  if (e is DioException) {
    final data = e.response?.data;
    if (data is Map) {
      // Prefer the specific field error ("A reason is required when clocking
      // in late.") over the top-level `message`, which some endpoints leave
      // as a generic "The given data was invalid." wrapper.
      final errs = data['errors'];
      if (errs is Map && errs.isNotEmpty) {
        final first = errs.values.first;
        if (first is List && first.isNotEmpty) return first.first.toString();
      }
      if (data['message'] is String) return data['message'] as String;
    }
    if (e.type == DioExceptionType.connectionError) {
      return 'No connection. Check your network and try again.';
    }
    return 'Request failed (${e.response?.statusCode ?? 'network'}).';
  }
  return 'Something went wrong.';
}
