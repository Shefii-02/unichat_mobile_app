import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:pretty_dio_logger/pretty_dio_logger.dart';
import '../constants/api_constants.dart';
import '../storage/secure_storage.dart';
import '../storage/local_storage.dart';

class DioClient {
  DioClient._();

  /// Set once at app bootstrap (see `app.dart`) so the auth interceptor below can mirror a
  /// storage-level sign-out into the app's in-memory session state. Without this, clearing
  /// SecureStorage on a 401 did nothing to `authProvider` itself — the router's `loggedIn`
  /// redirect check only ever reads that in-memory value, never storage — so a token going
  /// bad mid-session left the user stuck on whatever screen they were on, watching every
  /// subsequent request fail with 401, instead of being sent back to device re-login
  /// (QR/PIN). Deliberately a plain callback rather than importing Riverpod's authProvider
  /// here directly, to avoid a circular import (auth_repository.dart already imports this
  /// file).
  static void Function()? onAuthFailure;

  static Dio _buildDio(String baseUrl) {
    final dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: ApiConstants.connectTimeout,
      receiveTimeout: ApiConstants.receiveTimeout,
      headers: {'Accept': 'application/json', 'X-Client': 'mobile'},
    ));

    dio.interceptors.add(_AuthInterceptor());
    if (kDebugMode) {
      // responseBody stays off: a Laravel 500 dumps a multi-hundred-line PHP
      // stack trace, and PrettyDioLogger prints it synchronously, janking the
      // UI thread.
      dio.interceptors.add(PrettyDioLogger(
        requestHeader: false,
        requestBody: true,
        responseBody: false,
        error: true,
        compact: true,
      ));
    }
    return dio;
  }

  /// Shared in-flight refresh so concurrent 401s trigger one `/auth/refresh`, not several
  /// (the backend blacklists the old token on refresh, so a second call would fail).
  static Future<bool>? _refreshing;

  /// Slides an expired-but-still-refreshable access token forward (access TTL is 24h, refresh
  /// window 14 days) so the user isn't thrown back to the device login/scan screen every day.
  static Future<bool> refreshSession() {
    return _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);
  }

  static Future<bool> _doRefresh() async {
    try {
      final token = await SecureStorageService.getToken();
      if (token == null) return false;
      final res = await Dio(BaseOptions(
        baseUrl: ApiConstants.laravelBase,
        connectTimeout: ApiConstants.connectTimeout,
        receiveTimeout: ApiConstants.receiveTimeout,
        headers: {
          'Accept': 'application/json',
          'X-Client': 'mobile',
          'Authorization': 'Bearer $token',
          if (LocalStorage.getString(LocalStorage.kDeviceUid) != null)
            'X-Device-Uid': LocalStorage.getString(LocalStorage.kDeviceUid)!,
        },
      )).post('/auth/refresh');
      final fresh = (res.data as Map)['access_token'] as String?;
      if (fresh == null) return false;
      await SecureStorageService.saveToken(fresh);
      return true;
    } catch (_) {
      return false;
    }
  }

  static final laravelDio = _buildDio(ApiConstants.laravelBase);
  static final nodeDio    = _buildDio(ApiConstants.nodeBase);
  static final chatDio    = _buildDio(ApiConstants.chatBase);

  /// The client a request was built for, so a retry goes back to the same server.
  static Dio _dioFor(String baseUrl) {
    if (baseUrl == laravelDio.options.baseUrl) return laravelDio;
    if (baseUrl == chatDio.options.baseUrl) return chatDio;
    return nodeDio;
  }
}

/// `true` when the *token itself* was rejected — a normal 401/419, or the
/// backend's current (buggy) habit of returning 500 with a jwt-auth "Token has
/// expired" / "blacklisted" / "invalid" body. This is genuinely "sign the user
/// out" territory: we sent a token and the server says it's no good.
///
/// Deliberately does NOT include "Token not provided" — that means no token was
/// attached to *this request* at all, which on a device that just logged in
/// successfully is a client-side timing bug (see `_AuthInterceptor.onError`),
/// not proof the session is invalid. Treating it the same used to wipe a
/// perfectly good token seconds after saving it, cascading into a string of
/// identical failures (each retry also had no token, since the previous one
/// had just deleted it).
bool isAuthFailure(Response? res) {
  final code = res?.statusCode;
  if (code == 401 || code == 419) return true;
  // Admin turned off this account's mobile access — treat like a dead session.
  if (code == 403 && res?.data is Map && (res!.data as Map)['error_code'] == 'mobile_access_disabled') return true;
  if (code == 500 && res?.data is Map) {
    final data = res!.data as Map;
    final blob =
        '${data['message'] ?? ''} ${data['exception'] ?? ''}'.toLowerCase();
    return blob.contains('token has expired') ||
        blob.contains('token has been blacklisted') ||
        blob.contains('token could not be parsed') ||
        blob.contains('token is invalid') ||
        blob.contains('tokenexpiredexception') ||
        blob.contains('tokeninvalidexception');
  }
  return false;
}

/// `true` for the specific "no Authorization header made it to the server" case.
bool _isTokenMissing(Response? res) {
  if (res?.statusCode != 500 || res?.data is! Map) return false;
  final data = res!.data as Map;
  final blob = '${data['message'] ?? ''} ${data['exception'] ?? ''}'.toLowerCase();
  return blob.contains('token not provided') || blob.contains('tokennotfoundexception');
}

class _AuthInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    final token = await SecureStorageService.getToken();
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    final deviceUid = LocalStorage.getString(LocalStorage.kDeviceUid);
    if (deviceUid != null) {
      options.headers['X-Device-Uid'] = deviceUid;
    }
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (isAuthFailure(err.response)) {
      // Expired access token but still inside the refresh window: refresh and replay the
      // request once instead of signing the user out.
      final opts = err.requestOptions;
      final isAuthCall = opts.path.contains('/auth/login') || opts.path.contains('/auth/refresh');
      if (!isAuthCall && opts.extra['retried'] != true && await DioClient.refreshSession()) {
        try {
          final token = await SecureStorageService.getToken();
          opts.extra['retried'] = true;
          opts.headers['Authorization'] = 'Bearer $token';
          final retryDio = DioClient._dioFor(opts.baseUrl);
          handler.resolve(await retryDio.fetch(opts));
          return;
        } on DioException catch (e) {
          if (!isAuthFailure(e.response)) {
            handler.next(e);
            return;
          }
        } catch (_) {}
      }
      await SecureStorageService.clearAll();
      DioClient.onAuthFailure?.call();
      handler.next(err);
      return;
    }

    // "Token not provided" on a request that never got a Bearer header attached
    // (see onRequest) — if a token now exists in storage, this was a one-off
    // client race (e.g. the very first request right after a fresh device
    // login, firing before the just-saved token had propagated through to a
    // read), not an invalid session. Retry the same request once with the
    // token attached instead of wiping a token that's actually fine.
    if (_isTokenMissing(err.response) &&
        err.requestOptions.headers['Authorization'] == null) {
      final token = await SecureStorageService.getToken();
      if (token != null) {
        try {
          final retryOptions = err.requestOptions
            ..headers['Authorization'] = 'Bearer $token';
          final retryDio = DioClient._dioFor(retryOptions.baseUrl);
          final response = await retryDio.fetch(retryOptions);
          handler.resolve(response);
          return;
        } catch (_) {
          // Fall through — surface the original error.
        }
      }
    }

    handler.next(err);
  }
}
