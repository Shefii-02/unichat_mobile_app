import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:unichat_mobile_app/core/nav/app_modules.dart';
import 'package:unichat_mobile_app/core/network/api.dart';
import 'package:unichat_mobile_app/core/storage/local_storage.dart';

const _kHiddenModules = 'mobile_hidden_modules';

Set<String> _fromList(Object? v) =>
    v is List ? v.map((e) => '$e').toSet() : <String>{};

/// Tiles the superadmin hid for the mobile app (Superadmin → Mobile App Tiles on web).
/// Falls back to the last cached list when offline. Watch it so tile lists rebuild.
final mobileHiddenModulesProvider = FutureProvider<Set<String>>((ref) async {
  Set<String> hidden;
  try {
    final res = await Api.one('/mobile-modules/hidden');
    hidden = _fromList(res['hidden']);
    await LocalStorage.setJson(_kHiddenModules, {'hidden': hidden.toList()});
  } catch (_) {
    hidden = _fromList(LocalStorage.getJson(_kHiddenModules)?['hidden']);
  }
  AppModule.serverHidden = hidden;
  return hidden;
});
