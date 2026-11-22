import 'package:dio/dio.dart';
import 'package:unichat_mobile_app/core/network/dio_client.dart';
import 'package:unichat_mobile_app/core/storage/secure_storage.dart';
import 'package:unichat_mobile_app/core/storage/local_storage.dart';
import 'package:unichat_mobile_app/core/permissions/permission_guard.dart';
import 'device_auth_repository.dart';
import 'models/user_model.dart';

enum TokenRefreshResult { refreshed, invalid, networkError }

class AuthRepository {
  final _dio = DioClient.laravelDio;

  Future<UserModel> login({
    required String email,
    required String password,
  }) async {
    // The phone registers itself on every sign-in: over the account's phone limit the server answers 409 `device_limit` with the
    // phones to remove — thrown as a [DeviceLimitException] for the login page to turn into a "remove one to continue" sheet.
    final Response res;
    try {
      res = await _dio.post('/auth/login', data: {
        'email': email,
        'password': password,
        ...await DeviceAuthRepository().deviceFields(),
      });
    } on DioException catch (e) {
      if (DeviceLimitException.isLimitResponse(e)) {
        throw DeviceLimitException.fromJson(e.response!.data as Map<String, dynamic>);
      }
      rethrow;
    }

    // Response: { "data": { "access_token": "...", "user": { ... } } }
    final envelope = res.data as Map<String, dynamic>;
    final body     = envelope['data'] as Map<String, dynamic>;
    final token    = body['access_token'] as String;
    await SecureStorageService.saveToken(token);

    final user = UserModel.fromJson(body['user'] as Map<String, dynamic>);
    await LocalStorage.setJson(LocalStorage.kUser, user.toJson());
    PermissionGuard.setPermissions(user.permissions, user.role);
    PermissionGuard.setEntitlements(user.entitledModules);
    return user;
  }

  /// Frees one phone slot while signing in with email + password (see [DeviceLimitException.limitToken]) — the caller then repeats [login].
  Future<void> removeDevice({required String limitToken, required int deviceId}) async {
    try {
      await _dio.post('/auth/mobile-devices/remove', data: {'limit_token': limitToken, 'device_id': deviceId});
    } on DioException catch (e) {
      final data = e.response?.data;
      throw DeviceChallengeException(data is Map && data['message'] is String
          ? data['message'] as String
          : 'Could not remove that phone. Try again.');
    }
  }

  Future<UserModel?> getStoredUser() async {
    final json = LocalStorage.getJson(LocalStorage.kUser);
    if (json == null) return null;
    final user = UserModel.fromJson(json);
    PermissionGuard.setPermissions(user.permissions, user.role);
    PermissionGuard.setEntitlements(user.entitledModules);
    return user;
  }

  /// Called on cold start (see `AuthNotifier.verifyDevice`) to slide the session forward
  /// before checking anything else. `POST /auth/refresh` deliberately sits outside the
  /// backend's `jwt.auth` middleware, so this still works once the access token itself has
  /// expired — as long as it's within the refresh-TTL window — not just while the token is
  /// still technically valid.
  Future<TokenRefreshResult> refreshToken() async {
    try {
      final res = await _dio.post('/auth/refresh');
      final token = (res.data as Map<String, dynamic>)['access_token'] as String;
      await SecureStorageService.saveToken(token);
      return TokenRefreshResult.refreshed;
    } on DioException catch (e) {
      if (isAuthFailure(e.response)) return TokenRefreshResult.invalid;
      return TokenRefreshResult.networkError;
    }
  }

  Future<UserModel> validateToken() async {
    final res = await _dio.get('/auth/me');
    // Response: { "user": { ... } } or { "data": { "user": { ... } } }
    final raw  = res.data as Map<String, dynamic>;
    final body = raw['data'] as Map<String, dynamic>? ?? raw;
    final userMap = body['user'] as Map<String, dynamic>? ?? body;
    final user = UserModel.fromJson(userMap);
    await LocalStorage.setJson(LocalStorage.kUser, user.toJson());
    PermissionGuard.setPermissions(user.permissions, user.role);
    PermissionGuard.setEntitlements(user.entitledModules);
    return user;
  }

  Future<void> logout() async {
    try {
      await _dio.post('/auth/logout');
    } on DioException {
      // ignore network errors on logout
    } finally {
      await SecureStorageService.clearAll();
      await LocalStorage.clearSession();   // not clear(): theme, language, onboarding and the device id belong to the phone, not the person
      PermissionGuard.clear();
    }
  }
}
