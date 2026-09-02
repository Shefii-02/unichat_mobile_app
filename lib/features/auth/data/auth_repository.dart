import 'package:dio/dio.dart';
import 'package:unichat_mobile_app/core/network/dio_client.dart';
import 'package:unichat_mobile_app/core/storage/secure_storage.dart';
import 'package:unichat_mobile_app/core/storage/local_storage.dart';
import 'package:unichat_mobile_app/core/permissions/permission_guard.dart';
import 'models/user_model.dart';

class AuthRepository {
  final _dio = DioClient.laravelDio;

  Future<UserModel> login({
    required String email,
    required String password,
  }) async {
    final res = await _dio.post('/auth/login', data: {
      'email': email,
      'password': password,
    });

    // Response: { "data": { "access_token": "...", "user": { ... } } }
    final envelope = res.data as Map<String, dynamic>;
    final body     = envelope['data'] as Map<String, dynamic>;
    final token    = body['access_token'] as String;
    await SecureStorageService.saveToken(token);

    final user = UserModel.fromJson(body['user'] as Map<String, dynamic>);
    await LocalStorage.setJson(LocalStorage.kUser, user.toJson());
    PermissionGuard.setPermissions(user.permissions, user.role);
    return user;
  }

  Future<UserModel?> getStoredUser() async {
    final json = LocalStorage.getJson(LocalStorage.kUser);
    if (json == null) return null;
    final user = UserModel.fromJson(json);
    PermissionGuard.setPermissions(user.permissions, user.role);
    return user;
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
    return user;
  }

  Future<void> logout() async {
    try {
      await _dio.post('/auth/logout');
    } on DioException {
      // ignore network errors on logout
    } finally {
      await SecureStorageService.clearAll();
      await LocalStorage.clear();
      PermissionGuard.clear();
    }
  }
}
