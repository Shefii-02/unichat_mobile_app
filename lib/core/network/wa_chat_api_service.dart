// Dedicated API client for the WA Chat module (the open-wa gateway, deployed at
// unichatwa.univexa.in — a separate NestJS service, not this app's own Laravel backend).
//
// CRITICAL: this module talks ONLY to the unichatwa gateway. It must never share state
// with the Laravel API client (core/network/api.dart / dio_client.dart). Keep the base
// URL and auth mechanism (X-API-Key, the company's own `wa_chat_token`) separate from
// Laravel so the two backends can never be mixed — the gateway must never see the
// Laravel JWT, and the Laravel client must never see this API key.
//
// Laravel-proxied WA Chat calls (session lifecycle, automation rules, audit log, data
// export — everything that goes through `backend`'s own `/waha/*` and `/wa-*` routes
// instead of straight to the gateway) live in `features/modules/wa_chat_api.dart`
// instead; keep that split rather than adding Laravel calls here.
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:pretty_dio_logger/pretty_dio_logger.dart';
import 'package:unichat_mobile_app/core/constants/api_constants.dart';

/// Mirrors `frontend/src/pages/wa-chat/api/client.ts` + `api.ts`: a single isolated
/// client for the gateway, with one method per endpoint the app's WA Chat quick links
/// actually use. Every call takes the caller's own `apiKey` explicitly (the company's
/// `wa_chat_token`, read from `authProvider`) rather than caching it statically — unlike
/// the web SPA there is no long-lived sessionStorage slot to source it from, and a
/// reconnect (`WaChatApi.reconnectToken`) can mint a fresh key mid-session.
class WaChatApiService {
  WaChatApiService._();

  static final Dio _dio = _build();

  static Dio _build() {
    final dio = Dio(BaseOptions(
      baseUrl: ApiConstants.nodeBase,
      headers: {'Accept': 'application/json'},
    ));

    // Every WA Chat quick-link tab (Sessions, Chats, Dashboard, ...) fires one of these
    // calls the moment it opens — print method + full URL + query/body on the way out so
    // that's visible directly in the debug console, matching the logging `DioClient`
    // already gives the Laravel client (see dio_client.dart's own PrettyDioLogger).
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      // if (kDebugMode) {
      //   debugPrint('[WA Chat gateway] ${options.method} ${options.uri}'
      //       '${options.queryParameters.isNotEmpty ? '\n  query: ${options.queryParameters}' : ''}'
      //       '${options.data != null ? '\n  payload: ${options.data}' : ''}');
      // }
      handler.next(options);
    }));
    if (kDebugMode) {
      dio.interceptors.add(PrettyDioLogger(
        requestHeader: false,
        requestBody: true,
        responseBody: true,
        error: true,
        compact: true,
      ));
    }
    return dio;
  }

  static Options _auth(String apiKey) => Options(headers: {'X-API-Key': apiKey});

  // ═══════════════════════════ Dashboard aggregates ═══════════════════════════
  // Mirrors frontend/src/pages/wa-chat/pages/Dashboard.tsx, which calls these same
  // gateway routes with the company's own scoped key. All four are readable by an
  // OPERATOR-role scoped key (verified against the gateway's own guards): none of
  // them carry a @RequireUnscopedKey() fence, unlike session creation or /api/audit
  // (which is why session creation and the audit trail are Laravel-proxied instead —
  // see WaChatApi.createSession / WaChatApi.auditLog).

  /// `GET /api/sessions` — auto-scoped server-side to this key's own sessions.
  static Future<List<Map<String, dynamic>>> getSessions(String apiKey) async {
    final res = await _dio.get('/api/sessions', options: _auth(apiKey));
    final data = res.data;
    return data is List ? data.cast<Map<String, dynamic>>() : [];
  }

  /// `GET /api/sessions/stats/overview` — `{total, active, ready, disconnected, byStatus, memoryUsage}`.
  static Future<Map<String, dynamic>> getSessionStats(String apiKey) async {
    final res = await _dio.get('/api/sessions/stats/overview', options: _auth(apiKey));
    final data = res.data;
    return data is Map ? data.cast<String, dynamic>() : {};
  }

  /// `GET /api/webhooks` — this company's configured webhooks (any session).
  static Future<List<Map<String, dynamic>>> getWebhooks(String apiKey) async {
    final res = await _dio.get('/api/webhooks', options: _auth(apiKey));
    final data = res.data;
    return data is List ? data.cast<Map<String, dynamic>>() : [];
  }

  /// `GET /api/stats/overview` — `{sessions:{...}, messages:{sent,received,failed,today:{...}}}`.
  static Future<Map<String, dynamic>> getStatsOverview(String apiKey) async {
    final res = await _dio.get('/api/stats/overview', options: _auth(apiKey));
    final data = res.data;
    return data is Map ? data.cast<String, dynamic>() : {};
  }

  /// `GET /api/stats/messages?period=` — `{timeSeries:[{timestamp,sent,received}],
  /// byType:{[type]:count}, bySession:[...], topChats:[{chatId,chatName,messageCount}]}`.
  /// Backs the "Message Analytics" charts on the dashboard; `period` is `24h|7d|30d`.
  static Future<Map<String, dynamic>> getMessageStats(String apiKey, String period) async {
    final res = await _dio.get('/api/stats/messages',
        queryParameters: {'period': period}, options: _auth(apiKey));
    final data = res.data;
    return data is Map ? data.cast<String, dynamic>() : {};
  }

  // ═══════════════════════════ Session lifecycle ═══════════════════════════
  // Mirrors frontend/src/pages/wa-chat/pages/Sessions.tsx's sessionApi calls exactly — every one
  // of these is OPERATOR-role and carries no @RequireUnscopedKey() fence (verified against the
  // gateway's own guards), so the company's own scoped key can call them directly for any session
  // within its own allowlist. Session CREATE is the one exception (the gateway requires an
  // unscoped ADMIN key to mint a session at all) — that stays Laravel-proxied via
  // `WaChatApi.createSession`, which brokers it server-side with the gateway's real admin key.

  /// `POST /api/sessions/:id/start`.
  static Future<void> startSession(String sessionId, String apiKey) {
    return _dio.post('/api/sessions/${Uri.encodeComponent(sessionId)}/start', options: _auth(apiKey));
  }

  /// `POST /api/sessions/:id/stop` — used by the Dashboard's inline "Disconnect" action too.
  static Future<void> stopSession(String sessionId, String apiKey) {
    return _dio.post('/api/sessions/${Uri.encodeComponent(sessionId)}/stop', options: _auth(apiKey));
  }

  /// `POST /api/sessions/:id/logout` — unlinks the companion device; requires a fresh QR/pairing
  /// scan to reconnect afterwards (the gateway wipes stored credentials on a successful unlink).
  static Future<void> logoutSession(String sessionId, String apiKey) {
    return _dio.post('/api/sessions/${Uri.encodeComponent(sessionId)}/logout', options: _auth(apiKey));
  }

  /// `POST /api/sessions/:id/force-kill` — SIGKILLs a wedged engine, then tears the session down.
  static Future<void> forceKillSession(String sessionId, String apiKey) {
    return _dio.post('/api/sessions/${Uri.encodeComponent(sessionId)}/force-kill', options: _auth(apiKey));
  }

  /// `DELETE /api/sessions/:id`.
  static Future<void> deleteSession(String sessionId, String apiKey) {
    return _dio.delete('/api/sessions/${Uri.encodeComponent(sessionId)}', options: _auth(apiKey));
  }

  /// `GET /api/sessions/:id/qr` — `{qrCode: 'data:image/png;base64,...', status}`.
  static Future<Map<String, dynamic>> sessionQr(String sessionId, String apiKey) async {
    final res = await _dio.get('/api/sessions/${Uri.encodeComponent(sessionId)}/qr', options: _auth(apiKey));
    final data = res.data;
    return data is Map ? data.cast<String, dynamic>() : {};
  }

  /// `POST /api/sessions/:id/pairing-code` — `{pairingCode: 'ABCD1234', status}`, an alternative
  /// to scanning the QR: an 8-char code entered into WhatsApp's own "Link with phone number" flow.
  static Future<Map<String, dynamic>> requestPairingCode(
    String sessionId,
    String apiKey,
    String phoneNumber,
  ) async {
    final res = await _dio.post('/api/sessions/${Uri.encodeComponent(sessionId)}/pairing-code',
        data: {'phoneNumber': phoneNumber}, options: _auth(apiKey));
    final data = res.data;
    return data is Map ? data.cast<String, dynamic>() : {};
  }

  /// `GET /api/sessions/:id/groups/for-contact?contactId=&limit=` — every group this session and
  /// the given contact both belong to, matched server-side in one request. Backs the Contact Info
  /// panel's "Groups" tab.
  static Future<List<Map<String, dynamic>>> getSharedGroups(
    String sessionId,
    String apiKey,
    String contactId, {
    int limit = 100,
  }) async {
    final res = await _dio.get(
      '/api/sessions/${Uri.encodeComponent(sessionId)}/groups/for-contact',
      queryParameters: {'contactId': contactId, 'limit': limit},
      options: _auth(apiKey),
    );
    final data = res.data;
    return data is List ? data.cast<Map<String, dynamic>>() : [];
  }

  /// `GET /api/sessions/:id/contacts/:contactId/profile-picture` — `{url: string|null}`, a signed
  /// WhatsApp CDN link that expires in a few hours (mirrors `contactApi.profilePicture`). Null
  /// when the contact hid their picture or has none — callers should just fall back to initials.
  static Future<String?> getContactProfilePicture(String sessionId, String apiKey, String contactId) async {
    try {
      final res = await _dio.get(
        '/api/sessions/${Uri.encodeComponent(sessionId)}/contacts/${Uri.encodeComponent(contactId)}/profile-picture',
        options: _auth(apiKey),
      );
      final data = res.data;
      return data is Map ? data['url'] as String? : null;
    } catch (_) {
      return null;
    }
  }

  /// `GET /api/sessions/:id/contacts/:contactId/phone` — `{contactId, phone: string|null}`. On the
  /// Baileys engine a chat id is frequently an opaque `@lid` privacy id rather than a phone-number
  /// JID; this asks the engine to resolve the real MSISDN behind it (best-effort — `null` means the
  /// engine couldn't map it, not that the contact has no number). Errors are swallowed to `null`
  /// since the UI's only fallback either way is "phone number unknown".
  static Future<String?> resolveContactPhone(String sessionId, String apiKey, String contactId) async {
    try {
      final res = await _dio.get(
        '/api/sessions/${Uri.encodeComponent(sessionId)}/contacts/${Uri.encodeComponent(contactId)}/phone',
        options: _auth(apiKey),
      );
      final data = res.data;
      return data is Map ? data['phone'] as String? : null;
    } catch (_) {
      return null;
    }
  }

  /// `GET /api/sessions/:id/contacts/profile-pictures?ids=` — batch-resolves picture URLs for a
  /// whole chat list in ONE request. Mirrors `contactApi.profilePictures`: firing one request per
  /// tile instead exhausts the gateway's per-IP throttle (429s). Capped at 50 ids (matches the
  /// gateway's own cap) — any beyond that are silently dropped rather than sent and ignored.
  static Future<Map<String, String?>> getProfilePictures(
    String sessionId,
    String apiKey,
    List<String> contactIds,
  ) async {
    // Dio encodes queryParameters values itself — pre-encoding each id here (as the path-segment
    // calls elsewhere in this file correctly do) would double-encode them (`@` -> `%40` -> `%2540`),
    // so the gateway can never recover a valid JID from the ids list and every lookup comes back
    // empty. Join the raw ids and let Dio do the one encoding pass.
    final ids = contactIds.take(50).join(',');
    if (ids.isEmpty) return {};
    final res = await _dio.get(
      '/api/sessions/${Uri.encodeComponent(sessionId)}/contacts/profile-pictures',
      queryParameters: {'ids': ids},
      options: _auth(apiKey),
    );
    final pictures = res.data is Map ? res.data['pictures'] : null;
    return pictures is Map ? pictures.cast<String, String?>() : {};
  }

  // ═══════════════════════════ Chats & messages ═══════════════════════════
  // Mirrors frontend/src/pages/wa-chat/api/api.ts's sessionApi/messageApi exactly (same
  // gateway, same paths). The session id in every path below is the gateway's own
  // session name (`WahaSession.session_name` in Laravel), not the Laravel row's numeric id.

  /// `GET /api/sessions/:id/chats` — a bare array of chat summaries
  /// (`id, name, isGroup, kind, unreadCount, timestamp, lastMessage`).
  static Future<List<Map<String, dynamic>>> getChats(String sessionId, String apiKey) async {
    final res = await _dio.get('/api/sessions/${Uri.encodeComponent(sessionId)}/chats',
        options: _auth(apiKey));
    final data = res.data;
    // if (kDebugMode) {
    //   debugPrint('[WA Chat gateway] getChats($sessionId) → ${res.statusCode}, '
    //       '${data is List ? '${data.length} chat(s)' : 'unexpected body: $data'}');
    // }
    return data is List ? data.cast<Map<String, dynamic>>() : [];
  }

  /// `GET /api/sessions/:id/contacts` — a bare array of the session's own WhatsApp address book
  /// (`id, name?, pushName?, number, isMyContact, isBlocked, profilePicUrl?`). No server-side
  /// search — callers filter the fetched list client-side (same pattern as [getGroups]/[getChats]).
  /// Backs the campaign composer's "Contact" message tab (send-a-contact-card), which shares a
  /// WhatsApp contact from this session rather than a CRM one.
  static Future<List<Map<String, dynamic>>> getSessionContacts(String sessionId, String apiKey, {int limit = 1000}) async {
    final res = await _dio.get(
      '/api/sessions/${Uri.encodeComponent(sessionId)}/contacts',
      queryParameters: {'limit': limit},
      options: _auth(apiKey),
    );
    final data = res.data;
    // if (kDebugMode) {
    //   debugPrint('[WA Chat gateway] getSessionContacts($sessionId) → ${res.statusCode}, '
    //       '${data is List ? '${data.length} contact(s)' : 'unexpected body: $data'}');
    // }
    return data is List ? data.cast<Map<String, dynamic>>() : [];
  }

  /// `GET /api/sessions/:id/groups` — a bare array of `{id, name, linkedParentJID?}`. Backs the
  /// campaign composer's "Group" recipient tab.
  static Future<List<Map<String, dynamic>>> getGroups(String sessionId, String apiKey, {int limit = 1000}) async {
    final res = await _dio.get(
      '/api/sessions/${Uri.encodeComponent(sessionId)}/groups',
      queryParameters: {'limit': limit},
      options: _auth(apiKey),
    );
    final data = res.data;
    // if (kDebugMode) {
    //   debugPrint('[WA Chat gateway] getGroups($sessionId) → ${res.statusCode}, '
    //       '${data is List ? '${data.length} group(s)' : 'unexpected body: $data'}');
    // }
    return data is List ? data.cast<Map<String, dynamic>>() : [];
  }

  /// `GET /api/sessions/:id/groups/:groupId` — full group info including
  /// `participants: [{id, number, name?, isAdmin, isSuperAdmin}]`. Used to resolve a group
  /// selection into individual recipients for the campaign composer.
  static Future<Map<String, dynamic>> getGroupInfo(String sessionId, String apiKey, String groupId) async {
    final res = await _dio.get(
      '/api/sessions/${Uri.encodeComponent(sessionId)}/groups/${Uri.encodeComponent(groupId)}',
      options: _auth(apiKey),
    );
    final data = res.data;
    return data is Map ? data.cast<String, dynamic>() : {};
  }

  /// `GET /api/sessions/:id/labels` — this session's WhatsApp Business labels:
  /// `[{id, name, hexColor}]`. WhatsApp Business accounts only — the gateway answers 400 for a
  /// regular WhatsApp account, which callers should surface as "not a Business account" rather
  /// than a generic failure.
  static Future<List<Map<String, dynamic>>> getLabels(String sessionId, String apiKey) async {
    final res = await _dio.get('/api/sessions/${Uri.encodeComponent(sessionId)}/labels', options: _auth(apiKey));
    final data = res.data;
    return data is List ? data.cast<Map<String, dynamic>>() : [];
  }

  /// `GET /api/sessions/:id/labels/:labelId/chats` — every chat carrying that label:
  /// `[{id, name, isGroup, kind, unreadCount, timestamp, lastMessage?}]`. whatsapp-web.js only —
  /// the Baileys engine has no label-query capability at all and answers 501.
  static Future<List<Map<String, dynamic>>> getChatsByLabel(String sessionId, String apiKey, String labelId) async {
    final res = await _dio.get(
      '/api/sessions/${Uri.encodeComponent(sessionId)}/labels/${Uri.encodeComponent(labelId)}/chats',
      options: _auth(apiKey),
    );
    final data = res.data;
    return data is List ? data.cast<Map<String, dynamic>>() : [];
  }

  /// `GET /api/sessions/:id/messages?chatId=&limit=&after=` — `{messages: [...] (newest first),
  /// total}`. `after` is the gateway's keyset cursor (the `id` of the oldest row already fetched)
  /// for loading an older page — preferred over a plain offset because it anchors the window to a
  /// row rather than a count, so a message arriving mid-walk can't shift the page. Returns the raw
  /// `{messages, total}` map (not just the list) so a caller can tell whether more history remains.
  static Future<Map<String, dynamic>> getChatMessagesPage(
    String sessionId,
    String apiKey,
    String chatId, {
    int limit = 100,
    String? after,
  }) async {
    final res = await _dio.get(
      '/api/sessions/${Uri.encodeComponent(sessionId)}/messages',
      queryParameters: {'chatId': chatId, 'limit': limit, if (after != null) 'after': after},
      options: _auth(apiKey),
    );
    final data = res.data;
    return data is Map ? data.cast<String, dynamic>() : {'messages': [], 'total': 0};
  }

  /// Convenience wrapper over [getChatMessagesPage] for a caller that only wants the first page's
  /// messages, not the pagination metadata.
  static Future<List<Map<String, dynamic>>> getChatMessages(
    String sessionId,
    String apiKey,
    String chatId, {
    int limit = 100,
  }) async {
    final res = await getChatMessagesPage(sessionId, apiKey, chatId, limit: limit);
    final messages = res['messages'];
    return messages is List ? messages.cast<Map<String, dynamic>>() : [];
  }

  /// `GET /api/sessions/:id/messages/:chatId/history?limit=&includeMedia=` — live history
  /// fetched straight from WhatsApp via the engine, bypassing the DB entirely. A bare array of
  /// `EngineHistoryMessage` (different shape than [getChatMessages]'s DB rows — carries `fromMe`
  /// instead of `direction`/`status`). Backfills messages the gateway's own DB never captured
  /// (older history, or a gap from before the session was linked) — see `useChatMessages.ts`'s
  /// `mergeChatMessages`, which this mirrors: fetch both this and [getChatMessages], then merge.
  /// `includeMedia` defaults false to keep the payload light; recent media still renders from the
  /// DB copy, which wins on conflict.
  static Future<List<Map<String, dynamic>>> getChatHistory(
    String sessionId,
    String apiKey,
    String chatId, {
    int limit = 100,
    bool includeMedia = false,
  }) async {
    final res = await _dio.get(
      '/api/sessions/${Uri.encodeComponent(sessionId)}/messages/${Uri.encodeComponent(chatId)}/history',
      queryParameters: {'limit': limit, if (includeMedia) 'includeMedia': true},
      options: _auth(apiKey),
    );
    final data = res.data;
    return data is List ? data.cast<Map<String, dynamic>>() : [];
  }

  /// `POST /api/sessions/:id/chats/read` — marks a chat read.
  static Future<void> markChatRead(String sessionId, String apiKey, String chatId) {
    return _dio.post('/api/sessions/${Uri.encodeComponent(sessionId)}/chats/read',
        data: {'chatId': chatId}, options: _auth(apiKey));
  }

  /// `POST /api/sessions/:id/messages/send-text` — plain outgoing text message.
  static Future<void> sendText(String sessionId, String apiKey, String chatId, String text) {
    return _dio.post('/api/sessions/${Uri.encodeComponent(sessionId)}/messages/send-text',
        data: {'chatId': chatId, 'text': text}, options: _auth(apiKey));
  }

  /// `POST /api/sessions/:id/messages/reply` — quotes an existing message.
  static Future<void> reply(
    String sessionId,
    String apiKey, {
    required String chatId,
    required String quotedMessageId,
    required String text,
  }) {
    return _dio.post('/api/sessions/${Uri.encodeComponent(sessionId)}/messages/reply',
        data: {'chatId': chatId, 'quotedMessageId': quotedMessageId, 'text': text},
        options: _auth(apiKey));
  }

  /// `POST /api/sessions/:id/messages/react` — empty [emoji] removes a reaction.
  static Future<void> react(
    String sessionId,
    String apiKey, {
    required String chatId,
    required String messageId,
    required String emoji,
  }) {
    return _dio.post('/api/sessions/${Uri.encodeComponent(sessionId)}/messages/react',
        data: {'chatId': chatId, 'messageId': messageId, 'emoji': emoji},
        options: _auth(apiKey));
  }

  /// `POST /api/sessions/:id/messages/delete`.
  static Future<void> deleteMessage(
    String sessionId,
    String apiKey, {
    required String chatId,
    required String messageId,
    bool forEveryone = true,
  }) {
    return _dio.post('/api/sessions/${Uri.encodeComponent(sessionId)}/messages/delete',
        data: {'chatId': chatId, 'messageId': messageId, 'forEveryone': forEveryone},
        options: _auth(apiKey));
  }

  /// `POST /api/sessions/:id/messages/forward`.
  static Future<void> forward(
    String sessionId,
    String apiKey, {
    required String fromChatId,
    required String toChatId,
    required String messageId,
  }) {
    return _dio.post('/api/sessions/${Uri.encodeComponent(sessionId)}/messages/forward',
        data: {'fromChatId': fromChatId, 'toChatId': toChatId, 'messageId': messageId},
        options: _auth(apiKey));
  }

  /// `POST /api/sessions/:id/messages/send-{image|video|audio|document}` — mirrors
  /// `messageApi.sendMedia`. Exactly one of [base64]/[url] should be set; `base64` is raw (no
  /// `data:` prefix), matching the shape media already arrives in on a fetched message.
  static Future<void> sendMedia(
    String sessionId,
    String apiKey, {
    required String chatId,
    required String mediaType,
    String? base64,
    String? url,
    String? mimetype,
    String? filename,
    String? caption,
  }) {
    return _dio.post(
      '/api/sessions/${Uri.encodeComponent(sessionId)}/messages/send-$mediaType',
      data: {
        'chatId': chatId,
        if (base64 != null) 'base64': base64,
        if (url != null) 'url': url,
        if (mimetype != null) 'mimetype': mimetype,
        if (filename != null) 'filename': filename,
        if (caption != null) 'caption': caption,
      },
      options: _auth(apiKey),
    );
  }

  /// `POST /api/sessions/:id/messages/send-location`.
  static Future<void> sendLocation(
    String sessionId,
    String apiKey, {
    required String chatId,
    required double latitude,
    required double longitude,
    String? description,
    String? address,
  }) {
    return _dio.post(
      '/api/sessions/${Uri.encodeComponent(sessionId)}/messages/send-location',
      data: {
        'chatId': chatId,
        'latitude': latitude,
        'longitude': longitude,
        if (description != null) 'description': description,
        if (address != null) 'address': address,
      },
      options: _auth(apiKey),
    );
  }

  // ═══════════════════════════ Calls ═══════════════════════════

  /// `POST /api/sessions/:id/calls/link` — `{link}`, a shareable `call.whatsapp.com` link (the
  /// gateway can't place a real call; this only mints the link, same as WhatsApp's own "Share
  /// call link" — sending it as a chat message is on the caller). `startTime` has no "unset"
  /// value on the underlying whatsapp-web.js API, so "a link for right now" is
  /// `DateTime.now().millisecondsSinceEpoch`, not an omitted field.
  static Future<Map<String, dynamic>> generateCallLink(
    String sessionId,
    String apiKey, {
    required String type,
    required int startTime,
  }) async {
    final res = await _dio.post(
      '/api/sessions/${Uri.encodeComponent(sessionId)}/calls/link',
      data: {'type': type, 'startTime': startTime},
      options: _auth(apiKey),
    );
    final data = res.data;
    return data is Map ? data.cast<String, dynamic>() : {};
  }

  // ═══════════════════════════ Search ═══════════════════════════

  /// `GET /api/search` — full-text search over message *content*, across every session the key
  /// can see (unlike every other call in this file, the path itself isn't session-scoped;
  /// `sessionId` below is just an optional narrowing filter). Mirrors `searchApi.search` in
  /// frontend/src/pages/wa-chat/api/api.ts. Raises on the active provider being unavailable
  /// (501) or its worker not answering (503) — callers should catch and show that distinctly
  /// from a plain network error, as `GlobalSearch.tsx` does.
  static Future<Map<String, dynamic>> search(
    String apiKey, {
    required String q,
    String? sessionId,
    String? chatId,
    String? from,
    String? direction,
    String? type,
    int? dateFrom,
    int? dateTo,
    int limit = 20,
    int offset = 0,
  }) async {
    final res = await _dio.get(
      '/api/search',
      queryParameters: {
        'q': q,
        if (sessionId != null && sessionId.isNotEmpty) 'sessionId': sessionId,
        if (chatId != null && chatId.isNotEmpty) 'chatId': chatId,
        if (from != null && from.isNotEmpty) 'from': from,
        if (direction != null && direction.isNotEmpty) 'direction': direction,
        if (type != null && type.isNotEmpty) 'type': type,
        if (dateFrom != null) 'dateFrom': dateFrom,
        if (dateTo != null) 'dateTo': dateTo,
        'limit': limit,
        'offset': offset,
      },
      options: _auth(apiKey),
    );
    final data = res.data;
    return data is Map ? data.cast<String, dynamic>() : {'hits': [], 'total': 0};
  }
}
