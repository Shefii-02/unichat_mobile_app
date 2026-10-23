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

  static final laravelDio = _buildDio(ApiConstants.laravelBase);
  static final nodeDio    = _buildDio(ApiConstants.nodeBase);
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
          final retryDio = retryOptions.baseUrl == DioClient.laravelDio.options.baseUrl
              ? DioClient.laravelDio
              : DioClient.nodeDio;
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
