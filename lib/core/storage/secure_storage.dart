import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const _tokenKey    = 'auth_token';
  static const _phoneKey    = 'saved_phone';
  static const _passwordKey = 'saved_password';
  static const _orgIdKey    = 'saved_org_id';

  static Future<void> saveToken(String token) => _storage.write(key: _tokenKey, value: token);
  static Future<String?> getToken() => _storage.read(key: _tokenKey);
  static Future<void> deleteToken() => _storage.delete(key: _tokenKey);

  static Future<void> saveCredentials({
    required String orgId,
    required String phone,
    required String password,
  }) async {
    await _storage.write(key: _orgIdKey, value: orgId);
    await _storage.write(key: _phoneKey, value: phone);
    await _storage.write(key: _passwordKey, value: password);
  }

  static Future<Map<String, String?>> getSavedCredentials() async {
    return {
      'org_id':   await _storage.read(key: _orgIdKey),
      'phone':    await _storage.read(key: _phoneKey),
      'password': await _storage.read(key: _passwordKey),
    };
  }

  static Future<void> clearAll() => _storage.deleteAll();
}
