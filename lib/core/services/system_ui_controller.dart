import 'package:flutter/services.dart';
import 'package:unichat_mobile_app/core/storage/local_storage.dart';

/// Whether the app draws its content behind the status bar / gesture nav bar
/// ("edge to edge", the modern default on most phones) or leaves them their own
/// reserved strip the traditional way. Edge-to-edge looks better on most devices,
/// but a few phones' gesture nav bar visually overlaps app content when it's on —
/// exposed as a Settings toggle (see `_EdgeToEdgeTile`) so an affected user can
/// switch it off for their specific device instead of being stuck with the issue.
class SystemUiController {
  SystemUiController._();

  static Future<void> apply() async {
    final enabled = LocalStorage.getBool(LocalStorage.kEdgeToEdge, defaultValue: true);
    await SystemChrome.setEnabledSystemUIMode(
      enabled ? SystemUiMode.edgeToEdge : SystemUiMode.manual,
      overlays: enabled ? null : SystemUiOverlay.values,
    );
  }

  static Future<void> setEnabled(bool enabled) async {
    await LocalStorage.setBool(LocalStorage.kEdgeToEdge, enabled);
    await apply();
  }
}
