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

  /// What belongs to THIS PHONE rather than to whoever is signed in — theme, language, "onboarding seen", the PIN-setup prompt flag,
  /// the app's device id, the push token. Signing out must keep all of it: wiping it (the old `clear()`) re-showed the onboarding,
  /// reset the theme and language, and forgot the device id so every login registered the phone as a brand-new device.
  static const _deviceLevelKeys = {
    kThemeMode, kLanguage, kBiometric, kBioSensitive, kOnboardingSeen, kDeviceUid, kDeviceName, kPushToken,
    kAppLockSetupPromptSeen, kEdgeToEdge,
  };

  /// Sign-out: forget the signed-in person's cached data (profile, hidden modules, sticky notes …) but keep the phone's own settings.
  static Future<void> clearSession() async {
    for (final key in _p.getKeys().toList()) {
      if (!_deviceLevelKeys.contains(key)) await _p.remove(key);
    }
  }

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
  static const kAppLockSetupPromptSeen = 'app_lock_setup_prompt_seen';
  static const kEdgeToEdge = 'edge_to_edge_enabled';
}
