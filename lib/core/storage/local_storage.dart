import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class LocalStorage {
  LocalStorage._();

  static SharedPreferences? _prefs;

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  static SharedPreferences get _p {
    if (_prefs == null) throw StateError('LocalStorage not initialized');
    return _prefs!;
  }

  static Future<void> setString(String key, String value) => _p.setString(key, value);
  static String? getString(String key) => _p.getString(key);

  static Future<void> setBool(String key, bool value) => _p.setBool(key, value);
  static bool getBool(String key, {bool defaultValue = false}) => _p.getBool(key) ?? defaultValue;

  static Future<void> setInt(String key, int value) => _p.setInt(key, value);
  static int? getInt(String key) => _p.getInt(key);

  static Future<void> setJson(String key, Map<String, dynamic> value) =>
      _p.setString(key, jsonEncode(value));
  static Map<String, dynamic>? getJson(String key) {
    final s = _p.getString(key);
    if (s == null) return null;
    return jsonDecode(s) as Map<String, dynamic>;
  }

  static Future<void> remove(String key) => _p.remove(key);
  static Future<void> clear() => _p.clear();

  // App-specific keys
  static const kThemeMode = 'theme_mode';
  static const kLanguage  = 'language';
  static const kUser      = 'current_user';
  static const kBiometric = 'biometric_enabled';
  static const kBioSensitive = 'biometric_sensitive';
  static const kOnboardingSeen = 'onboarding_seen';
  static const kDeviceUid = 'device_uid';
  static const kDeviceName = 'device_name';
  static const kPushToken = 'push_token';
  static const kAppLockHintSeen = 'app_lock_hint_seen';
}
