import 'package:flutter/material.dart';
import 'package:new_version_plus/new_version_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Pure client-side update check (no backend) — looks up this app's own listing on the
/// Play Store / App Store and compares against the installed version.
class UpdateChecker {
  UpdateChecker._();
  static final _newVersion = NewVersionPlus();

  static Future<String> currentVersion() async {
    final info = await PackageInfo.fromPlatform();
    return info.version;
  }

  /// Silently checks and — only if an update is actually available — shows the native
  /// "Update available" dialog. Safe to call fire-and-forget; does nothing if [context] is
  /// gone by the time the (network) check resolves.
  static Future<void> checkAndAlertIfNeeded(BuildContext context) async {
    try {
      final status = await _newVersion.getVersionStatus();
      if (status != null && status.canUpdate && context.mounted) {
        _newVersion.showUpdateDialog(context: context, versionStatus: status);
      }
    } catch (_) {
      // Best-effort — no store listing yet, no network, etc. The manual "Check for
      // update" action in Settings surfaces the same failure to the user there.
    }
  }

  /// Manual "Check for update" action — always tells the user something, including
  /// "you're up to date," unlike the silent splash-screen check.
  static Future<void> checkManually(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final status = await _newVersion.getVersionStatus();
      if (status == null) {
        messenger.showSnackBar(const SnackBar(content: Text("Couldn't check for updates right now.")));
        return;
      }
      if (status.canUpdate) {
        if (context.mounted) _newVersion.showUpdateDialog(context: context, versionStatus: status);
      } else {
        messenger.showSnackBar(const SnackBar(content: Text("You're on the latest version.")));
      }
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text("Couldn't check for updates right now.")));
    }
  }
}
