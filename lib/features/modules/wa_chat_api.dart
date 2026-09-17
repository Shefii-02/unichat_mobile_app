import 'package:unichat_mobile_app/core/network/api.dart';

/// Every Laravel-side WA Chat quick-link endpoint, in one place — mirrors the
/// centralisation `frontend/src/pages/wa-chat/api/api.ts` gives the React app, kept
/// separate from `WaChatApiService` (calls straight to the open-wa gateway) and from
/// the page widgets that render the data these methods return.
class WaChatApi {
  WaChatApi._();

  // ── Sessions ─────────────────────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> sessions() => Api.list('/waha/sessions');

  static Future<Map<String, dynamic>> createSession(Map<String, dynamic> data) =>
      Api.post('/waha/sessions', data: data);

  static Future<void> deleteSession(int id) => Api.delete('/waha/sessions/$id');

  static Future<Map<String, dynamic>> startSession(int id) => Api.post('/waha/sessions/$id/start');

  static Future<Map<String, dynamic>> stopSession(int id) => Api.post('/waha/sessions/$id/stop');

  static Future<Map<String, dynamic>> logoutSession(int id) => Api.post('/waha/sessions/$id/logout');

  static Future<Map<String, dynamic>> forceKillSession(int id) => Api.post('/waha/sessions/$id/force-kill');

  static Future<Map<String, dynamic>> sessionQr(int id) => Api.one('/waha/sessions/$id/qr');

  static Future<Map<String, dynamic>> requestPairingCode(int id, String phoneNumber) =>
      Api.post('/waha/sessions/$id/pairing-code', data: {'phoneNumber': phoneNumber});

  static Future<Map<String, dynamic>> syncLabelsToCrm(int id) => Api.post('/waha/sessions/$id/labels/sync');

  // ── Contacts (per session) ──────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> sessionContacts(int sessionId) =>
      Api.list('/waha/sessions/$sessionId/contacts');

  static Future<void> syncContact(int sessionId, String contactId) =>
      Api.post('/waha/sessions/$sessionId/contacts/${Uri.encodeComponent(contactId)}/sync');

  static Future<Map<String, dynamic>> syncAllContacts(int sessionId) =>
      Api.post('/waha/sessions/$sessionId/contacts/sync');

  // ── Gateway token ────────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> reconnectToken() => Api.post('/waha/token/reconnect');

  // ── Automation rules ─────────────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> automationRules() => Api.list('/wa-agent/automations');

  static Future<Map<String, dynamic>> createAutomationRule(Map<String, dynamic> data) =>
      Api.post('/wa-agent/automations', data: data);

  static Future<Map<String, dynamic>> updateAutomationRule(dynamic id, Map<String, dynamic> data) =>
      Api.patch('/wa-agent/automations/$id', data: data);

  static Future<Map<String, dynamic>> toggleAutomationRule(dynamic id) =>
      Api.post('/wa-agent/automations/$id/toggle');

  static Future<void> deleteAutomationRule(dynamic id) => Api.delete('/wa-agent/automations/$id');

  static Future<List<Map<String, dynamic>>> automationLogs({Map<String, dynamic>? query}) =>
      Api.list('/wa-agent/automations/logs', query: query);

  // ── Analytics / audit ────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> analyticsOverview() => Api.one('/wa-chat/analytics');

  /// This company's own slice of the gateway's audit trail (see WahaSessionController::auditLog
  /// on the Laravel side for why this proxies through Laravel rather than calling the gateway's
  /// `/api/audit` directly — that route requires an ADMIN-role, unscoped gateway key, which a
  /// company's own scoped `wa_chat_token` can never be).
  static Future<Map<String, dynamic>> auditLog({String? severity, int limit = 50, int offset = 0}) =>
      Api.one('/waha/audit', query: {
        if (severity != null) 'severity': severity,
        'limit': limit,
        'offset': offset,
      });

  // ── Data export ──────────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> exportJobs() => Api.one('/wa-export');

  static Future<Map<String, dynamic>> exportChats(String sessionId) =>
      Api.post('/wa-export/chats', data: {'session_id': sessionId});

  static Future<Map<String, dynamic>> exportContacts(String sessionId) =>
      Api.post('/wa-export/contacts', data: {'session_id': sessionId});

  static Future<Map<String, dynamic>> exportGroups(String sessionId, {bool includeParticipants = false}) =>
      Api.post('/wa-export/groups', data: {
        'session_id': sessionId,
        'include_participants': includeParticipants,
      });

  static Future<void> deleteExportJob(int id) => Api.delete('/wa-export/$id');
}
