import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinput/pinput.dart';
import 'package:unichat_mobile_app/core/constants/app_colors.dart';
import 'package:unichat_mobile_app/core/theme/app_theme.dart';
import 'package:unichat_mobile_app/features/app_lock/app_lock_provider.dart';

/// Turning the app-lock PIN on / off — shared by Profile and Settings so both behave identically.

/// Create-then-confirm PIN in a sheet, then save it. Does nothing if the sheet is dismissed.
Future<void> turnOnAppLock(BuildContext context, WidgetRef ref) async {
  final pin = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => const SetPinSheet(),
  );
  if (pin == null || !context.mounted) return;
  await ref.read(appLockProvider.notifier).setPin(pin);
}

/// Asks first — turning it off lets anyone with the phone open the app (and drops biometric unlock too).
Future<void> turnOffAppLock(BuildContext context, WidgetRef ref) async {
  final state = ref.read(appLockProvider);
  final sure = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Turn off App Lock PIN?'),
      content: Text(
        state.biometricEnabled
            ? 'Anyone with this phone will be able to open Teamzo without a PIN or biometric. Biometric login will be turned off too.'
            : 'Anyone with this phone will be able to open Teamzo without a PIN.',
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

const _pinLength = 4;

/// Create-then-confirm PIN entry shown as a modal sheet when turning App Lock on from
/// Settings — pops with the chosen PIN on success, or `null` if dismissed. Mirrors the
/// visual style of the full-screen setup flow in `app_lock_page.dart`, but as a sheet since
/// this is an in-context Settings action, not a login-time redirect.
class SetPinSheet extends StatefulWidget {
  const SetPinSheet({super.key});
  @override
  State<SetPinSheet> createState() => _SetPinSheetState();
}

class _SetPinSheetState extends State<SetPinSheet> {
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
            Text('A $_pinLength-digit PIN to quickly unlock Teamzo on this phone.',
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

