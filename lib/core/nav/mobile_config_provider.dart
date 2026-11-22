import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:unichat_mobile_app/core/nav/app_modules.dart';
import 'package:unichat_mobile_app/core/network/api.dart';
import 'package:unichat_mobile_app/core/storage/local_storage.dart';

const _kMobileConfig = 'mobile_company_config';

/// What the company chose to show in the app (web: Settings → Mobile App). Everything defaults to shown, so a failed
/// load never hides anything the company didn't hide.
class MobileConfig {
  const MobileConfig({
    this.tabs = const {},
    this.profileItems = const {},
    this.hiddenModules = const {},
  });
  final Map<String, bool> tabs;
  final Map<String, bool> profileItems;
  final Set<String> hiddenModules;

  bool tab(String key) => tabs[key] != false;
  bool profileItem(String key) => profileItems[key] != false;

  static Map<String, bool> _bools(Object? v) =>
      v is Map
          ? {for (final e in v.entries) '${e.key}': e.value == true}
          : <String, bool>{};

  factory MobileConfig.fromJson(Map<String, dynamic>? j) => MobileConfig(
    tabs: _bools(j?['tabs']),
    profileItems: _bools(j?['profile_items']),
    hiddenModules:
        j?['hidden_modules'] is List
            ? (j!['hidden_modules'] as List).map((e) => '$e').toSet()
            : <String>{},
  );
}

/// Loaded once per session (cached for offline). Also feeds the company's hidden Explore tiles into [AppModule].
final mobileConfigProvider = FutureProvider<MobileConfig>((ref) async {
  Map<String, dynamic>? json;
  try {
    json = await Api.one('/mobile-config');
    await LocalStorage.setJson(_kMobileConfig, json);
  } catch (_) {
    json = LocalStorage.getJson(_kMobileConfig);
  }
  final cfg = MobileConfig.fromJson(json);
  AppModule.companyHidden = cfg.hiddenModules;
  return cfg;
});
