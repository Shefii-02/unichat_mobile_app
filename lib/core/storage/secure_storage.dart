import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const _tokenKey    = 'auth_token';
  static const _phoneKey    = 'saved_phone';
  static const _passwordKey = 'saved_password';
  static const _orgIdKey    = 'saved_org_id';
  static const _mpinHashKey = 'app_lock_mpin_hash';
  static const _biometricEnabledKey = 'app_lock_biometric_enabled';

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

  /// Wipes saved auth/credentials on logout — but keeps the device's app-lock MPIN and
  /// biometric preference. The lock is a property of this phone, not of any one account: a
  /// fresh login on the same device offers to reuse it rather than forcing a new one every
  /// time someone logs back in.
  static Future<void> clearAll() async {
    final mpinHash = await getMpinHash();
    final biometric = await _storage.read(key: _biometricEnabledKey);
    await _storage.deleteAll();
    if (mpinHash != null) await _storage.write(key: _mpinHashKey, value: mpinHash);
    if (biometric != null) await _storage.write(key: _biometricEnabledKey, value: biometric);
  }

  // ── App lock (MPIN + biometric) — device-local only, never sent to the server.
  // Cleared on logout via [clearAll], so a fresh device login always asks the user to set a
  // new MPIN (or, per [saveMpinHash]'s caller, offers to reuse one still on this device).
  static Future<void> saveMpinHash(String hash) => _storage.write(key: _mpinHashKey, value: hash);
  static Future<String?> getMpinHash() => _storage.read(key: _mpinHashKey);
  static Future<void> clearMpin() => _storage.delete(key: _mpinHashKey);
  static Future<bool> hasMpin() async => (await getMpinHash()) != null;

  static Future<void> setBiometricEnabled(bool v) =>
      _storage.write(key: _biometricEnabledKey, value: v ? 'true' : 'false');
  static Future<bool> isBiometricEnabled() async =>
      (await _storage.read(key: _biometricEnabledKey)) == 'true';
}
