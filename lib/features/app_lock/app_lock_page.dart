import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pinput/pinput.dart';
import 'package:unichat_mobile_app/core/constants/app_colors.dart';
import 'package:unichat_mobile_app/core/theme/app_theme.dart';
import 'package:unichat_mobile_app/features/auth/presentation/providers/auth_provider.dart';
import 'app_lock_provider.dart';

const _pinLength = 4;

/// The one screen for both "unlock" (MPIN exists, app is locked) and "reset the PIN without
/// the old one" (MPIN exists, but the user just logged back in, proving identity another
/// way) — first-time setup lives at `AppLockSetupPromptPage` instead, since that flow needs
/// to be skippable and this one must not be. Which of the two shows here is decided once —
/// the first time [AppLockState.loaded] flips true — and then frozen for this page
/// instance's lifetime: [_SetupOrResetView] calls `resetPin` partway through its own flow
/// (to ask about enabling biometric *after* saving the PIN), which flips `justAuthenticated`
/// in the provider — if this widget kept reacting to that live, it would swap out from under
/// the view mid-flow and dispose its State while a dialog it opened was still awaiting a
/// button tap. Only `context.go(redirectTo)` (called explicitly at the end of each view)
/// ever leaves this page.
class AppLockPage extends ConsumerStatefulWidget {
  const AppLockPage({super.key, this.redirectTo = '/home'});
  final String redirectTo;

  @override
  ConsumerState<AppLockPage> createState() => _AppLockPageState();
}

class _AppLockPageState extends ConsumerState<AppLockPage> {
  bool? _showUnlock;
  bool _wasMpinSetAtEntry = false;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appLockProvider);
    if (!state.loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!state.hasMpin) {
      // This route is only ever reached pre-`loaded`, as a fail-safe while the provider is
      // still resolving. Now that we know there's no MPIN, there's nothing to unlock or set
      // up — bounce straight on. (The router's own redirect won't do this for us: it only
      // fires when navigating *to* a new location, and we're already sitting on this one.)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go(widget.redirectTo);
      });
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_showUnlock == null) {
      _showUnlock = !state.justAuthenticated;
      _wasMpinSetAtEntry = state.hasMpin;
    }
    // _UnlockView paints its own full-bleed gradient background (including behind the status
    // bar) and manages its own SafeArea, so it isn't nested inside one here like the setup
    // flow is.
    return _showUnlock!
        ? _UnlockView(redirectTo: widget.redirectTo)
        : Scaffold(
            body: SafeArea(
              child: _SetupOrResetView(redirectTo: widget.redirectTo, isReset: _wasMpinSetAtEntry),
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
    final biometricEnabled = ref.watch(appLockProvider.select((s) => s.biometricEnabled));
    final name = ref.watch(authProvider).value?.name;
    final firstName = (name == null || name.trim().isEmpty) ? null : name.trim().split(' ').first;

    final defaultPin = PinTheme(
      width: 52, height: 58,
      textStyle: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(25),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withAlpha(60)),
      ),
    );

    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.primaryDark, AppColors.primary],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 76, height: 76,
                          decoration: BoxDecoration(
                            color: Colors.white.withAlpha(30),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Icon(Icons.lock_rounded, color: Colors.white, size: 40),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          firstName != null ? 'Welcome back, $firstName' : 'Welcome back',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 6),
                        const Text('Enter your PIN to continue',
                            style: TextStyle(color: Colors.white70, fontSize: 13)),
                        const SizedBox(height: 32),
                        Pinput(
                          controller: _pinCtrl,
                          length: _pinLength,
                          obscureText: true,
                          enabled: !_busy,
                          defaultPinTheme: defaultPin,
                          focusedPinTheme: defaultPin.copyWith(
                            decoration: defaultPin.decoration!.copyWith(
                              border: Border.all(color: Colors.white, width: 1.6),
                            ),
                          ),
                          onCompleted: _submit,
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 16),
                          Text(_error!, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                        ],
                        if (_busy) ...[
                          const SizedBox(height: 20),
                          const SizedBox(
                            width: 22, height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              // Pinned to the bottom, above the safe-area inset — biometric is a shortcut on
              // top of the PIN above, never a replacement, so it always sits secondary to it.
              if (biometricEnabled)
                Padding(
                  padding: const EdgeInsets.only(bottom: 28, top: 4),
                  child: Column(
                    children: [
                      InkWell(
                        borderRadius: BorderRadius.circular(36),
                        onTap: _tryBiometric,
                        child: Container(
                          width: 64, height: 64,
                          decoration: BoxDecoration(
                            color: Colors.white.withAlpha(30),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white.withAlpha(70)),
                          ),
                          child: const Icon(Icons.fingerprint_rounded, color: Colors.white, size: 34),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text('Use biometric', style: TextStyle(color: Colors.white70, fontSize: 12.5)),
                    ],
                  ),
                ),
            ],
          ),
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
        builder: (dialogCtx) => AlertDialog(
          title: const Text('Enable biometric unlock?'),
          content: const Text('Use your fingerprint or face to unlock faster. Your PIN still works as a backup.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogCtx, false), child: const Text('Not now')),
            FilledButton(onPressed: () => Navigator.pop(dialogCtx, true), child: const Text('Enable')),
          ],
        ),
      );
      if (enable == true) {
        final err = await notifier.enableBiometric();
        if (err != null && mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('$err You can try again later in Settings.')));
        }
      }
    }
    if (mounted) context.go(widget.redirectTo);
  }

  void _reset() {
    setState(() { _firstPin = null; _error = null; _pinCtrl.clear(); _confirmCtrl.clear(); });
  }

  /// Skipping the post-login PIN reset turns app lock off entirely, rather than leaving the
  /// old PIN in place — "Skip" here is a deliberate opt-out of app lock on this device, not
  /// just "no thanks, I'll keep my old PIN." A future login is free to opt back in via the
  /// first-time setup prompt or Settings.
  Future<void> _skip() async {
    await ref.read(appLockProvider.notifier).disableMpin();
    if (mounted) context.go(widget.redirectTo);
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

    return Column(
      children: [
        if (widget.isReset)
          Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 8, top: 4),
              child: TextButton(onPressed: _busy ? null : _skip, child: const Text('Skip')),
            ),
          ),
        Expanded(child: _buildForm(context, theme, defaultPin, entering)),
      ],
    );
  }

  Widget _buildForm(BuildContext context, ThemeData theme, PinTheme defaultPin, bool entering) {
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
              Text(
                widget.isReset
                    ? "You already have an app lock PIN on this phone. Set a new one now, "
                        'or tap Skip above to turn app lock off entirely for this device.'
                    : 'A $_pinLength-digit PIN to quickly unlock Flowexa on this phone.',
                textAlign: TextAlign.center,
                style: TextStyle(color: context.mutedColor, fontSize: 13, height: 1.4),
              ),
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
