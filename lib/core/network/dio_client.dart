import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:pretty_dio_logger/pretty_dio_logger.dart';
import '../constants/api_constants.dart';
import '../storage/secure_storage.dart';
import '../storage/local_storage.dart';

class DioClient {
  DioClient._();

  static Dio _buildDio(String baseUrl) {
    final dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: ApiConstants.connectTimeout,
      receiveTimeout: ApiConstants.receiveTimeout,
      headers: {'Accept': 'application/json'},
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

/// `true` when the response means "this session is no longer valid" — a normal
/// 401/419, or the backend's current (buggy) habit of returning 500 with a
/// jwt-auth "Token has expired" / "blacklisted" / "invalid" body.
bool isAuthFailure(Response? res) {
  final code = res?.statusCode;
  if (code == 401 || code == 419) return true;
  if (code == 500 && res?.data is Map) {
    final data = res!.data as Map;
    final blob =
        '${data['message'] ?? ''} ${data['exception'] ?? ''}'.toLowerCase();
    return blob.contains('token has expired') ||
        blob.contains('token has been blacklisted') ||
        blob.contains('token could not be parsed') ||
        blob.contains('token is invalid') ||
        blob.contains('unauthorizedhttpexception') ||
        blob.contains('tokenexpiredexception') ||
        blob.contains('tokeninvalidexception');
  }
  return false;
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
    }
    handler.next(err);
  }
}
