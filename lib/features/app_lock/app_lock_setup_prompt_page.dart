import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pinput/pinput.dart';
import 'package:unichat_mobile_app/core/storage/local_storage.dart';
import 'package:unichat_mobile_app/core/theme/app_theme.dart';
import 'app_lock_provider.dart';

const _pinLength = 4;

/// Shown exactly once, right after a fresh login, on a device that has never set up an app
/// lock PIN — offers to set one (skippable), then, only if a PIN was actually set and
/// biometrics are available, offers to enable biometric on top of it (skippable too).
/// Skipping or finishing either step marks the prompt seen for good (see
/// [LocalStorage.kAppLockSetupPromptSeen]) — it never asks again; from then on, MPIN and
/// biometric are reachable only as an opt-in from Settings.
class AppLockSetupPromptPage extends ConsumerStatefulWidget {
  const AppLockSetupPromptPage({super.key, this.redirectTo = '/home'});
  final String redirectTo;

  @override
  ConsumerState<AppLockSetupPromptPage> createState() => _AppLockSetupPromptPageState();
}

class _AppLockSetupPromptPageState extends ConsumerState<AppLockSetupPromptPage> {
  final _pinCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  String? _firstPin;
  String? _error;
  bool _busy = false;
  bool _askBiometric = false;

  @override
  void dispose() {
    _pinCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    await LocalStorage.setBool(LocalStorage.kAppLockSetupPromptSeen, true);
    if (mounted) context.go(widget.redirectTo);
  }

  /// The top-right "Skip" button, while still on the PIN step (no PIN created yet) — makes
  /// it explicit and idempotent that skipping here leaves the device with app lock properly
  /// *disabled*, not just "untouched", even if some stray MPIN/biometric state already
  /// existed on this device from before. Once biometric is being asked about, a PIN has
  /// already been saved in this same flow — Skip/"Not now" there must never undo it, so that
  /// path goes through [_finish] directly instead.
  Future<void> _skipEntirely() async {
    await ref.read(appLockProvider.notifier).disableMpin();
    await _finish();
  }

  void _onFirstComplete(String pin) => setState(() { _firstPin = pin; _error = null; });

  Future<void> _onConfirmComplete(String pin) async {
    if (pin != _firstPin) {
      _confirmCtrl.clear();
      setState(() => _error = "PINs don't match — try again.");
      return;
    }
    setState(() => _busy = true);
    await ref.read(appLockProvider.notifier).setPin(pin);
    if (!mounted) return;
    final biometricAvailable = ref.read(appLockProvider).biometricAvailable;
    if (biometricAvailable) {
      setState(() { _busy = false; _askBiometric = true; });
    } else {
      await _finish();
    }
  }

  Future<void> _enableBiometric() async {
    setState(() => _busy = true);
    final err = await ref.read(appLockProvider.notifier).enableBiometric();
    if (!mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    }
    await _finish();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 8, top: 4),
                child: TextButton(
                  onPressed: _busy ? null : (_askBiometric ? _finish : _skipEntirely),
                  child: const Text('Skip'),
                ),
              ),
            ),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: _askBiometric ? _biometricStep(context) : _pinStep(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pinStep(BuildContext context) {
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

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.lock_outline_rounded, size: 44, color: theme.colorScheme.primary),
        const SizedBox(height: 16),
        Text(entering ? 'Set up an app lock PIN' : 'Confirm your PIN',
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        if (entering)
          Text(
            'Protect Teamzo with a $_pinLength-digit PIN on this phone. You can turn this on '
            "later from Settings instead — this only ever asks once.",
            textAlign: TextAlign.center,
            style: TextStyle(color: context.mutedColor, fontSize: 13, height: 1.4),
          ),
        const SizedBox(height: 24),
        entering
            ? Pinput(
                key: const ValueKey('first'),
                controller: _pinCtrl,
                length: _pinLength,
                obscureText: true,
                enabled: !_busy,
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
                enabled: !_busy,
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
          TextButton(
            onPressed: () => setState(() {
              _firstPin = null;
              _error = null;
              _pinCtrl.clear();
              _confirmCtrl.clear();
            }),
            child: const Text('Start over'),
          ),
        ],
      ],
    );
  }

  Widget _biometricStep(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.fingerprint_rounded, size: 44, color: theme.colorScheme.primary),
        const SizedBox(height: 16),
        Text('Enable biometric login?',
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text(
          'Use your fingerprint or face to unlock faster. Your PIN still works as a backup.',
          textAlign: TextAlign.center,
          style: TextStyle(color: context.mutedColor, fontSize: 13, height: 1.4),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: _busy ? null : _enableBiometric,
          icon: const Icon(Icons.fingerprint_rounded),
          label: const Text('Enable'),
        ),
        const SizedBox(height: 8),
        TextButton(onPressed: _busy ? null : _finish, child: const Text('Not now')),
      ],
    );
  }
}
