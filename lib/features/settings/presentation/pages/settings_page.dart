import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:unichat_mobile_app/core/constants/app_colors.dart';
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
          if (user != null)
            Container(
              padding: const EdgeInsets.all(20),
              color: AppColors.primary.withAlpha(10),
              child: Row(
                children: [
                  AppAvatar(name: user.name, size: 56),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(user.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                        Text(user.role.toUpperCase(), style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                        Text(user.companyName ?? '', style: const TextStyle(color: AppColors.textLight, fontSize: 12)),
                      ],
                    ),
                  ),
                  IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () => context.push('/edit-profile')),
                ],
              ),
            ),

          const SizedBox(height: 8),

          _section('Appearance', [const _ThemeTile()]),

          _section('Notifications', [const _NotificationPermissionTile(), const _NotificationSection()]),

          _section('Security', [
            _tile(Icons.lock_outline, 'Change Password', trailing: const Icon(Icons.chevron_right),
                onTap: () => _showChangePassword(context)),
            _tile(Icons.devices_rounded, 'Linked Devices',
                subtitle: 'Manage devices signed in to this account',
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/devices')),
            _tile(Icons.pin_outlined, 'Change App Lock PIN', trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/change-mpin')),
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
              ref.read(authProvider.notifier).logout();
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
    if (_status == null) return const SizedBox.shrink();
    return ListTile(
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
    );
  }
}

class _NotificationSection extends ConsumerWidget {
  const _NotificationSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(notificationPreferencesProvider);
    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(16),
        child: Text(apiErrorMessage(e), style: const TextStyle(color: AppColors.error, fontSize: 12)),
      ),
      data: (res) {
        final prefs = (res['data'] is Map) ? (res['data'] as Map) : const {};
        return Column(
          children: _notificationLabels.entries.map((e) {
            final key = e.key;
            final (label, subtitle) = e.value;
            final value = prefs[key] == true;
            return SwitchListTile(
              value: value,
              onChanged: (v) async {
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
          }).toList(),
        );
      },
    );
  }
}

class _BiometricTile extends ConsumerWidget {
  const _BiometricTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appLockProvider);
    if (!state.biometricAvailable) return const SizedBox.shrink();
    return ListTile(
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
                final ok = await ref.read(appLockProvider.notifier).enableBiometric();
                if (!ok && context.mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(const SnackBar(content: Text("Couldn't verify biometrics.")));
                }
              },
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
