import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pinput/pinput.dart';
import 'package:unichat_mobile_app/core/theme/app_theme.dart';
import 'app_lock_provider.dart';

const _pinLength = 4;

/// The one screen for both "set up app lock" (no MPIN yet) and "unlock" (MPIN exists,
/// app is locked) — which one shows is entirely driven by [AppLockState], not a route
/// argument, so it always reflects the true current state.
class AppLockPage extends ConsumerWidget {
  const AppLockPage({super.key, this.redirectTo = '/home'});
  final String redirectTo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appLockProvider);
    if (!state.loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      body: SafeArea(
        child: state.hasMpin && !state.justAuthenticated
            ? _UnlockView(redirectTo: redirectTo)
            : _SetupOrResetView(redirectTo: redirectTo, isReset: state.hasMpin),
      ),
    );
  }
}

class _UnlockView extends ConsumerStatefulWidget {
  const _UnlockView({required this.redirectTo});
  final String redirectTo;
  @override
  ConsumerState<_UnlockView> createState() => _UnlockViewState();
}

class _UnlockViewState extends ConsumerState<_UnlockView> {
  final _pinCtrl = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final s = ref.read(appLockProvider);
    if (s.biometricEnabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _tryBiometric());
    }
  }

  @override
  void dispose() {
    _pinCtrl.dispose();
    super.dispose();
  }

  Future<void> _tryBiometric() async {
    final ok = await ref.read(appLockProvider.notifier).authenticateWithBiometric();
    if (ok && mounted) context.go(widget.redirectTo);
  }

  Future<void> _submit(String pin) async {
    setState(() { _busy = true; _error = null; });
    final ok = await ref.read(appLockProvider.notifier).verifyPin(pin);
    if (!mounted) return;
    if (ok) {
      context.go(widget.redirectTo);
      return;
    }
    _pinCtrl.clear();
    setState(() { _busy = false; _error = 'Incorrect PIN.'; });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final biometricEnabled = ref.watch(appLockProvider.select((s) => s.biometricEnabled));
    final defaultPin = PinTheme(
      width: 52, height: 58,
      textStyle: theme.textTheme.titleLarge,
      decoration: BoxDecoration(
        color: context.altSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.lineColor),
      ),
    );

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_rounded, size: 44, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text('Enter your app lock PIN',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 24),
            Pinput(
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
              onCompleted: _submit,
            ),
            if (_error != null) ...[
              const SizedBox(height: 14),
              Text(_error!, style: const TextStyle(color: AppPalette.danger, fontSize: 13)),
            ],
            if (biometricEnabled) ...[
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: _tryBiometric,
                icon: const Icon(Icons.fingerprint_rounded),
                label: const Text('Use biometric'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Also used for "reset" (right after a fresh login, [AppLockState.justAuthenticated]) —
/// same create-then-confirm flow, just skipping old-PIN verification since identity was
/// already proven by the login itself.
class _SetupOrResetView extends ConsumerStatefulWidget {
  const _SetupOrResetView({required this.redirectTo, required this.isReset});
  final String redirectTo;
  final bool isReset;
  @override
  ConsumerState<_SetupOrResetView> createState() => _SetupOrResetViewState();
}

class _SetupOrResetViewState extends ConsumerState<_SetupOrResetView> {
  final _pinCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  String? _firstPin;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _pinCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _onFirstComplete(String pin) async {
    setState(() { _firstPin = pin; _error = null; });
  }

  Future<void> _onConfirmComplete(String pin) async {
    if (pin != _firstPin) {
      _confirmCtrl.clear();
      setState(() => _error = "PINs don't match — try again.");
      return;
    }
    setState(() => _busy = true);
    final notifier = ref.read(appLockProvider.notifier);
    await (widget.isReset ? notifier.resetPin(pin) : notifier.setPin(pin));
    if (!mounted) return;

    final biometricAvailable = ref.read(appLockProvider).biometricAvailable;
    if (biometricAvailable) {
      final enable = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          title: const Text('Enable biometric unlock?'),
          content: const Text('Use your fingerprint or face to unlock faster. Your PIN still works as a backup.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Not now')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Enable')),
          ],
        ),
      );
      if (enable == true) {
        final ok = await notifier.enableBiometric();
        if (!ok && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Couldn't verify biometrics — you can enable this later in Settings.")));
        }
      }
    }
    if (mounted) context.go(widget.redirectTo);
  }

  void _reset() {
    setState(() { _firstPin = null; _error = null; _pinCtrl.clear(); _confirmCtrl.clear(); });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final defaultPin = PinTheme(
      width: 52, height: 58,
      textStyle: theme.textTheme.titleLarge,
      decoration: BoxDecoration(
        color: context.altSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.lineColor),
      ),
    );
    final entering = _firstPin == null;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline_rounded, size: 44, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text(
              entering
                  ? (widget.isReset ? 'Set a new app lock PIN' : 'Create your app lock PIN')
                  : 'Confirm your PIN',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            if (entering)
              Text('A $_pinLength-digit PIN to quickly unlock Flowexa on this phone.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: context.mutedColor, fontSize: 13, height: 1.4)),
            const SizedBox(height: 24),
            if (entering)
              Pinput(
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
            else
              Pinput(
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
              const SizedBox(height: 16),
              TextButton(onPressed: _reset, child: const Text('Start over')),
            ],
          ],
        ),
      ),
    );
  }
}
