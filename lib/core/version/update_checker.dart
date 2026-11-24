import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:new_version_plus/new_version_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:unichat_mobile_app/core/storage/local_storage.dart';

/// Update checks. No backend: on Android the Play Store's own in-app update API (reliable, and it can download in the background); on iOS —
/// or when the app wasn't installed from Play — a look-up of the store listing, which can only point the user at the store.
///
/// Opening the app checks once per session (see [UpdateOnOpen]). With **Auto update** on (Profile → Settings, on by default) an available
/// version downloads in the background and the user is asked to restart; with it off the user gets an "Update available" prompt instead.
class UpdateChecker {
  UpdateChecker._();
  static final _newVersion = NewVersionPlus();

  static const kAutoUpdate = 'auto_update_enabled';
  static const _kSnoozeVersion = 'update_snoozed_version';
  static const _kSnoozeUntil = 'update_snoozed_until';

  static bool get autoUpdate => LocalStorage.getBool(kAutoUpdate, defaultValue: true);
  static Future<void> setAutoUpdate(bool on) => LocalStorage.setBool(kAutoUpdate, on);
  static bool get _isAndroid => !kIsWeb && Platform.isAndroid;

  static Future<String> currentVersion() async => (await PackageInfo.fromPlatform()).version;

  /// App-open check. Silent when up to date, offline, or when this version's prompt was dismissed within the last day.
  static Future<void> checkOnAppOpen(BuildContext context) async {
    try {
      if (_isAndroid && await _androidFlow(context, manual: false)) return;
      if (!context.mounted) return;
      await _storeListingFlow(context, manual: false);
    } catch (_) {
      // best-effort: no Play listing yet, no network, sideloaded build …  The manual check in Settings reports these.
    }
  }

  /// Settings → "Check for update": always tells the user something.
  static Future<void> checkManually(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (_isAndroid && await _androidFlow(context, manual: true)) return;
      if (!context.mounted) return;
      final handled = await _storeListingFlow(context, manual: true);
      if (!handled) messenger.showSnackBar(const SnackBar(content: Text("You're on the latest version.")));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text("Couldn't check for updates right now.")));
    }
  }

  // ── Android: Google Play in-app updates ───────────────────────────────────────────────────────────────────────────────────────
  /// Returns true when Play answered (update shown / started, or nothing to do); false to fall back to the store-listing check.
  static Future<bool> _androidFlow(BuildContext context, {required bool manual}) async {
    final AppUpdateInfo info;
    try {
      info = await InAppUpdate.checkForUpdate();
    } catch (_) {
      return false;   // not installed from Play (debug / sideload) — fall back
    }
    if (info.updateAvailability != UpdateAvailability.updateAvailable) {
      return !manual ? true : false;   // up to date — on a manual check the caller says so
    }
    final version = '${info.availableVersionCode ?? ''}';
    if (!manual && _snoozed(version)) return true;

    if (autoUpdate && info.flexibleUpdateAllowed) {
      final result = await InAppUpdate.startFlexibleUpdate();   // downloads in the background
      if (result == AppUpdateResult.success && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('A new version has been downloaded.'),
          duration: const Duration(seconds: 12),
          action: SnackBarAction(label: 'Restart', onPressed: () => InAppUpdate.completeFlexibleUpdate()),
        ));
      }
      return true;
    }
    if (!context.mounted) return true;
    final go = await _ask(context, 'Update available', 'A new version of Teamzo is available. Update now to get the latest features and fixes.');
    if (go == true) {
      if (info.immediateUpdateAllowed) {
        await InAppUpdate.performImmediateUpdate();
      } else if (info.flexibleUpdateAllowed) {
        await InAppUpdate.startFlexibleUpdate();
      }
    } else if (!manual) {
      await _snooze(version);
    }
    return true;
  }

  // ── iOS / fallback: the store listing ─────────────────────────────────────────────────────────────────────────────────────────
  static Future<bool> _storeListingFlow(BuildContext context, {required bool manual}) async {
    final status = await _newVersion.getVersionStatus();
    if (status == null || !status.canUpdate) return false;
    if (!manual && _snoozed(status.storeVersion)) return true;
    if (!context.mounted) return true;
    _newVersion.showUpdateDialog(context: context, versionStatus: status);
    if (!manual) await _snooze(status.storeVersion);   // don't nag again for a day
    return true;
  }

  static Future<bool?> _ask(BuildContext context, String title, String body) => showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Later')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Update')),
          ],
        ),
      );

  static bool _snoozed(String version) {
    if (LocalStorage.getString(_kSnoozeVersion) != version) return false;
    final until = int.tryParse(LocalStorage.getString(_kSnoozeUntil) ?? '') ?? 0;
    return DateTime.now().millisecondsSinceEpoch < until;
  }

  static Future<void> _snooze(String version) async {
    await LocalStorage.setString(_kSnoozeVersion, version);
    await LocalStorage.setString(_kSnoozeUntil, '${DateTime.now().add(const Duration(days: 1)).millisecondsSinceEpoch}');
  }
}

/// Wrap the signed-in app frame with this: it runs the update check once per app session, after the first frame — when the screen is
/// stable. (The old check ran on the splash screen, which navigates away within a second, so its prompt was usually never shown.)
class UpdateOnOpen extends StatefulWidget {
  const UpdateOnOpen({super.key, required this.child});
  final Widget child;
  static bool _doneThisSession = false;
  @override
  State<UpdateOnOpen> createState() => _UpdateOnOpenState();
}

class _UpdateOnOpenState extends State<UpdateOnOpen> {
  @override
  void initState() {
    super.initState();
    if (UpdateOnOpen._doneThisSession) return;
    UpdateOnOpen._doneThisSession = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future<void>.delayed(const Duration(seconds: 2));   // let Home settle before prompting
      if (mounted) await UpdateChecker.checkOnAppOpen(context);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
