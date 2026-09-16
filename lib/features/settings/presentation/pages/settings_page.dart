import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:pinput/pinput.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:unichat_mobile_app/core/constants/app_colors.dart';
import 'package:unichat_mobile_app/core/services/system_ui_controller.dart';
import 'package:unichat_mobile_app/core/storage/local_storage.dart';
import 'package:unichat_mobile_app/core/theme/theme_provider.dart';
import 'package:unichat_mobile_app/core/version/update_checker.dart';
import 'package:unichat_mobile_app/core/widgets/app_avatar.dart';
import 'package:unichat_mobile_app/features/app_lock/app_lock_provider.dart';
import 'package:unichat_mobile_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:unichat_mobile_app/features/modules/_shared.dart';
import 'package:unichat_mobile_app/features/modules/module_providers.dart';
import 'package:unichat_mobile_app/features/settings/legal_webview_sheet.dart';

// Placeholder — swap for the real hosted URL once available.
const _privacyPolicyUrl = 'https://flowexa.app/legal/privacy';
const _termsUrl = 'https://flowexa.app/legal/terms';
const _supportEmail = 'support@flowexa.app';

const _notificationLabels = <String, (String, String)>{
  'new_lead_alert':        ('New lead alerts', 'A new lead is assigned to you'),
  'ai_handoff_offers':     ('AI handoff offers', 'The AI hands a chat back to you'),
  'sla_breach_alert':      ('SLA breach alerts', 'A response deadline is about to be missed'),
  'campaign_updates':      ('Campaign updates', 'Broadcast/campaign status changes'),
  'leave_request_updates': ('Leave request updates', 'Your leave is approved, rejected, or reviewed'),
  'payroll_released':      ('Payroll released', 'A new payslip is available'),
  'attendance_reminders':  ('Attendance reminders', 'Clock-in/clock-out and break nudges'),
};

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).value;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          // Always present (never `if (user != null) ...`) — inserting/removing this item
          // from a plain ListView's children as `user` resolves from null shifts every
          // sibling below it in the same frame the app-lock/notification tiles further down
          // are also changing shape, which was tripping Flutter's semantics-flush assertion
          // ("!semantics.parentDataDirty"). Keeping one stable widget and only swapping its
          // text content avoids that entirely, matching every other tile on this page.
          Container(
            padding: const EdgeInsets.all(20),
            color: AppColors.primary.withAlpha(10),
            child: Row(
              children: [
                AppAvatar(name: user?.name ?? '', size: 56),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user?.name ?? '…', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                      Text((user?.role ?? '').toUpperCase(), style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                      Text(user?.companyName ?? '', style: const TextStyle(color: AppColors.textLight, fontSize: 12)),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: user == null ? null : () => context.push('/edit-profile'),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          _section('Appearance', [const _ThemeTile(), const _EdgeToEdgeTile()]),

          _section('Notifications', [const _NotificationPermissionTile(), const _NotificationSection()]),

          _section('Security', [
            _tile(Icons.lock_outline, 'Change Password', trailing: const Icon(Icons.chevron_right),
                onTap: () => _showChangePassword(context)),
            _tile(Icons.devices_rounded, 'Linked Devices',
                subtitle: 'Manage devices signed in to this account',
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/devices')),
            const _AppLockTile(),
            const _ChangeMpinTile(),
            const _BiometricTile(),
          ]),

          _section('About', [
            const _VersionTile(),
            _tile(Icons.support_agent, 'Support', subtitle: _supportEmail,
                trailing: const Icon(Icons.chevron_right),
                onTap: () => launchUrl(Uri.parse('mailto:$_supportEmail?subject=Flowexa%20support'))),
            _tile(Icons.privacy_tip_outlined, 'Privacy Policy', trailing: const Icon(Icons.chevron_right),
                onTap: () => showLegalSheet(context, title: 'Privacy Policy', url: _privacyPolicyUrl)),
            _tile(Icons.description_outlined, 'Terms of Service', trailing: const Icon(Icons.chevron_right),
                onTap: () => showLegalSheet(context, title: 'Terms of Service', url: _termsUrl)),
          ]),

          const SizedBox(height: 16),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ElevatedButton.icon(
              onPressed: () => _confirmLogout(context, ref),
              icon: const Icon(Icons.logout),
              label: const Text('Logout'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _section(String title, List<Widget> tiles) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textLight, letterSpacing: 0.8)),
        ),
        ...tiles,
        const Divider(height: 1),
      ],
    );
  }

  static Widget _tile(IconData icon, String label, {String? subtitle, Widget? trailing, VoidCallback? onTap}) {
    return ListTile(
      leading: Icon(icon, color: AppColors.textSecondary, size: 22),
      title: Text(label, style: const TextStyle(fontSize: 14)),
      subtitle: subtitle != null ? Text(subtitle, style: const TextStyle(fontSize: 12, color: AppColors.textLight)) : null,
      trailing: trailing,
      onTap: onTap ?? () {},
    );
  }

  void _confirmLogout(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Logout?'),
        content: const Text('You will be signed out and redirected to the login screen.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              ref.read(authProvider.notifier).logout(clearAppLock: true);
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
  }

  void _showChangePassword(BuildContext context) {
    final current = TextEditingController();
    final next = TextEditingController();
    final confirm = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Change Password'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: current, obscureText: true, decoration: const InputDecoration(labelText: 'Current password')),
            const SizedBox(height: 8),
            TextField(controller: next, obscureText: true, decoration: const InputDecoration(labelText: 'New password')),
            const SizedBox(height: 8),
            TextField(controller: confirm, obscureText: true, decoration: const InputDecoration(labelText: 'Confirm new password')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final ok = await runAction(
                ctx,
                () => Api.post('/auth/change-password', data: {
                  'current_password': current.text,
                  'password': next.text,
                  'password_confirmation': confirm.text,
                }),
                success: 'Password changed.',
              );
              if (ok && ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

class _ThemeTile extends ConsumerWidget {
  const _ThemeTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    final label = switch (mode) {
      ThemeMode.light => 'Light',
      ThemeMode.dark => 'Dark',
      ThemeMode.system => 'System default',
    };
    return ListTile(
      leading: const Icon(Icons.dark_mode_outlined, color: AppColors.textSecondary, size: 22),
      title: const Text('Theme', style: TextStyle(fontSize: 14)),
      subtitle: Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textLight)),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => showModalBottomSheet(
        context: context,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: ThemeMode.values.map((m) {
              final l = switch (m) {
                ThemeMode.light => 'Light',
                ThemeMode.dark => 'Dark',
                ThemeMode.system => 'System default',
              };
              return RadioListTile<ThemeMode>(
                value: m,
                groupValue: mode,
                title: Text(l),
                onChanged: (v) {
                  if (v != null) ref.read(themeModeProvider.notifier).set(v);
                  Navigator.pop(ctx);
                },
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}

/// Edge-to-edge draws app content behind the status bar / gesture nav bar, like most modern
/// apps — but on a handful of phones, the gesture nav bar visually overlaps content when
/// it's on. Rather than forcing one behavior for every device, this is a manual escape
/// hatch: default on, and a user hitting that overlap issue on their specific phone can turn
/// it off here. Takes effect immediately, no restart needed.
class _EdgeToEdgeTile extends StatefulWidget {
  const _EdgeToEdgeTile();
  @override
  State<_EdgeToEdgeTile> createState() => _EdgeToEdgeTileState();
}

class _EdgeToEdgeTileState extends State<_EdgeToEdgeTile> {
  bool _enabled = LocalStorage.getBool(LocalStorage.kEdgeToEdge, defaultValue: true);

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      secondary: const Icon(Icons.fullscreen_rounded, color: AppColors.textSecondary, size: 22),
      title: const Text('Full-screen edge to edge', style: TextStyle(fontSize: 14)),
      subtitle: const Text(
        'App content draws behind the status/nav bar. Turn off if your phone\'s '
        'gesture bar overlaps the app.',
        style: TextStyle(fontSize: 11.5, color: AppColors.textLight),
      ),
      value: _enabled,
      activeThumbColor: AppColors.primary,
      onChanged: (v) {
        setState(() => _enabled = v);
        SystemUiController.setEnabled(v);
      },
    );
  }
}

/// The OS-level permission — separate from the in-app category toggles below. If this is
/// off, none of those toggles matter: the system blocks every notification regardless.
class _NotificationPermissionTile extends StatefulWidget {
  const _NotificationPermissionTile();
  @override
  State<_NotificationPermissionTile> createState() => _NotificationPermissionTileState();
}

class _NotificationPermissionTileState extends State<_NotificationPermissionTile>
    with WidgetsBindingObserver {
  PermissionStatus? _status;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Catches a permission granted/revoked via the OS Settings app while this page sat
    // in the background.
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final status = await Permission.notification.status;
    if (mounted) setState(() => _status = status);
  }

  @override
  Widget build(BuildContext context) {
    final granted = _status?.isGranted ?? true;
    // Swapping straight to/from SizedBox.shrink() destroys and recreates this tile's
    // RenderObject the instant `_refresh()`'s async result lands — when several sibling
    // tiles in this same ListView do that in the same frame (as happens here alongside the
    // app-lock tiles below), Flutter's semantics flush can crash with
    // "!semantics.parentDataDirty". Visibility(maintainState: true) keeps the subtree alive
    // instead of tearing it down, which avoids that race.
    return Visibility(
      visible: _status != null,
      maintainState: true,
      maintainAnimation: true,
      maintainSize: false,
      child: ListTile(
        leading: Icon(granted ? Icons.notifications_active_outlined : Icons.notifications_off_outlined,
            color: granted ? AppColors.success : AppColors.error, size: 22),
        title: const Text('Allow notifications', style: TextStyle(fontSize: 14)),
        subtitle: Text(
          granted ? 'Enabled for this app' : 'Off — none of the categories below can notify you',
          style: TextStyle(fontSize: 11.5, color: granted ? AppColors.textLight : AppColors.error),
        ),
        trailing: granted
            ? null
            : FilledButton(
                onPressed: () async {
                  if (_status == PermissionStatus.permanentlyDenied) {
                    await openAppSettings();
                  } else {
                    await Permission.notification.request();
                  }
                  _refresh();
                },
                child: const Text('Enable'),
              ),
      ),
    );
  }
}

class _NotificationSection extends ConsumerWidget {
  const _NotificationSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(notificationPreferencesProvider);
    // `Api.one` already unwraps the server's `{data: {...}}` envelope one level, so `prefs`
    // here IS the preference fields flat — do not index `['data']` again.
    final prefs = async.value;
    // Deliberately always renders the same 7-tile Column, loading or not — swapping this
    // for a CircularProgressIndicator while it loads (and back) changes the widget shape at
    // the exact moment several *other* tiles on this page are also flipping shape (the
    // app-lock tiles above, once appLockProvider resolves), which was crashing the Flutter
    // semantics flush with "!semantics.parentDataDirty". Keeping the shape stable and just
    // toggling enabled/value avoids that entirely.
    return Column(
      children: [
        if (async.hasError)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(apiErrorMessage(async.error!), style: const TextStyle(color: AppColors.error, fontSize: 12)),
          ),
        ..._notificationLabels.entries.map((e) {
          final key = e.key;
          final (label, subtitle) = e.value;
          final value = prefs?[key] == true;
          return SwitchListTile(
            value: value,
            onChanged: prefs == null
                ? null
                : (v) async {
                    ref.invalidate(notificationPreferencesProvider);
                    try {
                      await Api.raw.put('/notification-preferences/me', data: {key: v});
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
                      }
                    } finally {
                      ref.invalidate(notificationPreferencesProvider);
                    }
                  },
            secondary: const Icon(Icons.notifications_outlined, color: AppColors.textSecondary, size: 22),
            title: Text(label, style: const TextStyle(fontSize: 14)),
            subtitle: Text(subtitle, style: const TextStyle(fontSize: 11.5, color: AppColors.textLight)),
            activeThumbColor: AppColors.primary,
          );
        }),
      ],
    );
  }
}

/// Master on/off for device app-lock. Turning it on runs a create-PIN flow; turning it off
/// clears the PIN (and, since biometric only ever sits on top of a PIN, biometric too).
class _AppLockTile extends ConsumerWidget {
  const _AppLockTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appLockProvider);
    // See the comment on _NotificationPermissionTile — this, _ChangeMpinTile and
    // _BiometricTile all used to swap to SizedBox.shrink() based on the same
    // appLockProvider.refresh() resolving, which flips all three at once and was
    // triggering a Flutter semantics-flush crash. Visibility(maintainState: true) instead.
    return Visibility(
      visible: state.loaded,
      maintainState: true,
      maintainAnimation: true,
      maintainSize: false,
      child: SwitchListTile(
        secondary: const Icon(Icons.pin_outlined, color: AppColors.textSecondary, size: 22),
        title: const Text('App Lock PIN', style: TextStyle(fontSize: 14)),
        subtitle: Text(
          state.hasMpin ? 'Require a PIN to open Flowexa on this phone' : 'Off — anyone with this phone can open the app',
          style: const TextStyle(fontSize: 11.5, color: AppColors.textLight),
        ),
        value: state.hasMpin,
        activeThumbColor: AppColors.primary,
        onChanged: (v) => v ? _enable(context, ref) : _disable(context, ref),
      ),
    );
  }

  Future<void> _enable(BuildContext context, WidgetRef ref) async {
    final pin = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => const _SetPinSheet(),
    );
    if (pin == null || !context.mounted) return;
    await ref.read(appLockProvider.notifier).setPin(pin);
  }

  Future<void> _disable(BuildContext context, WidgetRef ref) async {
    final state = ref.read(appLockProvider);
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Turn off App Lock PIN?'),
        content: Text(
          state.biometricEnabled
              ? 'Anyone with this phone will be able to open Flowexa without a PIN or biometric. Biometric login will be turned off too.'
              : 'Anyone with this phone will be able to open Flowexa without a PIN.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Turn off'),
          ),
        ],
      ),
    );
    if (sure == true) await ref.read(appLockProvider.notifier).disableMpin();
  }
}

/// Only meaningful once a PIN already exists — hidden otherwise (use the toggle above).
class _ChangeMpinTile extends ConsumerWidget {
  const _ChangeMpinTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasMpin = ref.watch(appLockProvider.select((s) => s.hasMpin));
    return Visibility(
      visible: hasMpin,
      maintainState: true,
      maintainAnimation: true,
      maintainSize: false,
      child: SettingsPage._tile(Icons.password_rounded, 'Change App Lock PIN',
          trailing: const Icon(Icons.chevron_right), onTap: () => context.push('/change-mpin')),
    );
  }
}

class _BiometricTile extends ConsumerWidget {
  const _BiometricTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appLockProvider);
    return Visibility(
      visible: state.biometricAvailable,
      maintainState: true,
      maintainAnimation: true,
      maintainSize: false,
      child: ListTile(
        leading: const Icon(Icons.fingerprint, color: AppColors.textSecondary, size: 22),
        title: const Text('Biometric Login', style: TextStyle(fontSize: 14)),
        subtitle: !state.hasMpin
            ? const Text('Set an app lock PIN first', style: TextStyle(fontSize: 11.5, color: AppColors.textLight))
            : null,
        trailing: Switch(
          value: state.biometricEnabled,
          activeThumbColor: AppColors.primary,
          onChanged: !state.hasMpin
              ? null
              : (v) async {
                  if (!v) {
                    await ref.read(appLockProvider.notifier).setBiometricEnabled(false);
                    return;
                  }
                  final err = await ref.read(appLockProvider.notifier).enableBiometric();
                  if (err != null && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
                  }
                },
        ),
      ),
    );
  }
}

const _pinLength = 4;

/// Create-then-confirm PIN entry shown as a modal sheet when turning App Lock on from
/// Settings — pops with the chosen PIN on success, or `null` if dismissed. Mirrors the
/// visual style of the full-screen setup flow in `app_lock_page.dart`, but as a sheet since
/// this is an in-context Settings action, not a login-time redirect.
class _SetPinSheet extends StatefulWidget {
  const _SetPinSheet();
  @override
  State<_SetPinSheet> createState() => _SetPinSheetState();
}

class _SetPinSheetState extends State<_SetPinSheet> {
  final _pinCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  String? _firstPin;
  String? _error;

  @override
  void dispose() {
    _pinCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  void _onFirstComplete(String pin) => setState(() { _firstPin = pin; _error = null; });

  void _onConfirmComplete(String pin) {
    if (pin != _firstPin) {
      _confirmCtrl.clear();
      setState(() => _error = "PINs don't match — try again.");
      return;
    }
    Navigator.of(context).pop(pin);
  }

  void _reset() => setState(() { _firstPin = null; _error = null; _pinCtrl.clear(); _confirmCtrl.clear(); });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entering = _firstPin == null;
    final defaultPin = PinTheme(
      width: 52, height: 58,
      textStyle: theme.textTheme.titleLarge,
      decoration: BoxDecoration(
        color: context.altSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.lineColor),
      ),
    );
    return Padding(
      padding: EdgeInsets.only(
        left: 24, right: 24, top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_outline_rounded, size: 40, color: theme.colorScheme.primary),
          const SizedBox(height: 12),
          Text(entering ? 'Create your app lock PIN' : 'Confirm your PIN',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          if (entering) ...[
            const SizedBox(height: 8),
            Text('A $_pinLength-digit PIN to quickly unlock Flowexa on this phone.',
                textAlign: TextAlign.center,
                style: TextStyle(color: context.mutedColor, fontSize: 13, height: 1.4)),
          ],
          const SizedBox(height: 20),
          entering
              ? Pinput(
                  key: const ValueKey('first'),
                  controller: _pinCtrl,
                  length: _pinLength,
                  obscureText: true,
                  defaultPinTheme: defaultPin,
                  focusedPinTheme: defaultPin.copyWith(
                    decoration: defaultPin.decoration!.copyWith(
                      border: Border.all(color: theme.colorScheme.primary, width: 1.6),
                    ),
                  ),
                  onCompleted: _onFirstComplete,
                )
              : Pinput(
                  key: const ValueKey('confirm'),
                  controller: _confirmCtrl,
                  length: _pinLength,
                  obscureText: true,
                  defaultPinTheme: defaultPin,
                  focusedPinTheme: defaultPin.copyWith(
                    decoration: defaultPin.decoration!.copyWith(
                      border: Border.all(color: theme.colorScheme.primary, width: 1.6),
                    ),
                  ),
                  onCompleted: _onConfirmComplete,
                ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            Text(_error!, style: const TextStyle(color: AppPalette.danger, fontSize: 13)),
          ],
          if (!entering) ...[
            const SizedBox(height: 12),
            TextButton(onPressed: _reset, child: const Text('Start over')),
          ],
        ],
      ),
    );
  }
}

class _VersionTile extends StatefulWidget {
  const _VersionTile();
  @override
  State<_VersionTile> createState() => _VersionTileState();
}

class _VersionTileState extends State<_VersionTile> {
  String? _version;

  @override
  void initState() {
    super.initState();
    UpdateChecker.currentVersion().then((v) { if (mounted) setState(() => _version = v); });
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.info_outline, color: AppColors.textSecondary, size: 22),
      title: const Text('Version', style: TextStyle(fontSize: 14)),
      subtitle: Text(_version ?? '…', style: const TextStyle(fontSize: 12, color: AppColors.textLight)),
      trailing: TextButton(
        onPressed: () => UpdateChecker.checkManually(context),
        child: const Text('Check for update'),
      ),
    );
  }
}
