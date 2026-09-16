import 'package:dio/dio.dart';

/// Talks directly to the open-wa gateway microservice (NOT the Laravel API) —
/// mirrors `frontend/src/pages/wa-chat/api/client.ts`, which calls this same
/// host with the company's own `wa_chat_token` as `X-API-Key`. Deliberately a
/// separate Dio instance with no shared interceptors: this gateway must never
/// see the Laravel JWT, and the Laravel client must never see this API key.
class WaGatewayClient {
  WaGatewayClient._();

  static const _baseUrl = 'https://unichatwa.univexa.in';
  static final Dio _dio = Dio(BaseOptions(
    baseUrl: _baseUrl,
    headers: {'Accept': 'application/json'},
  ));

  /// `GET /api/audit` — company-scoped WA gateway audit trail. Returns
  /// `{data: AuditLogEntry[], total: int}`; entries use camelCase fields
  /// (`sessionName`, `statusCode`, `createdAt`, ...) since this is the
  /// gateway's own Node-style API, not Laravel.
  static Future<Map<String, dynamic>> auditLogs(
    String apiKey, {
    String? action,
    String? severity,
    int limit = 50,
    int offset = 0,
  }) async {
    final res = await _dio.get('/api/audit',
        queryParameters: {
          if (action != null) 'action': action,
          if (severity != null) 'severity': severity,
          'limit': limit,
          'offset': offset,
        },
        options: Options(headers: {'X-API-Key': apiKey}));
    final data = res.data;
    return data is Map ? data.cast<String, dynamic>() : {'data': [], 'total': 0};
  }
}
