import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinput/pinput.dart';
import 'package:unichat_mobile_app/core/theme/app_theme.dart';
import 'app_lock_provider.dart';

const _pinLength = 4;

enum _Step { verifyOld, enterNew, confirmNew }

/// Verify the current PIN, then create-and-confirm a new one. Reachable from Settings —
/// unlike the post-login reset flow, this always requires the old PIN first.
class ChangeMpinPage extends ConsumerStatefulWidget {
  const ChangeMpinPage({super.key});
  @override
  ConsumerState<ChangeMpinPage> createState() => _ChangeMpinPageState();
}

class _ChangeMpinPageState extends ConsumerState<ChangeMpinPage> {
  var _step = _Step.verifyOld;
  final _ctrl = TextEditingController();
  String? _newPin;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _onComplete(String value) async {
    setState(() { _busy = true; _error = null; });
    switch (_step) {
      case _Step.verifyOld:
        final ok = await ref.read(appLockProvider.notifier).verifyPin(value);
        if (!mounted) return;
        if (!ok) {
          _ctrl.clear();
          setState(() { _busy = false; _error = 'Incorrect current PIN.'; });
          return;
        }
        setState(() { _step = _Step.enterNew; _busy = false; });
        _ctrl.clear();
      case _Step.enterNew:
        setState(() { _newPin = value; _step = _Step.confirmNew; _busy = false; });
        _ctrl.clear();
      case _Step.confirmNew:
        if (value != _newPin) {
          _ctrl.clear();
          setState(() { _busy = false; _error = "PINs don't match — try again."; _step = _Step.enterNew; _newPin = null; });
          return;
        }
        await ref.read(appLockProvider.notifier).setPin(value);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PIN updated.')));
        Navigator.of(context).pop();
    }
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
    final title = switch (_step) {
      _Step.verifyOld => 'Enter your current PIN',
      _Step.enterNew => 'Enter a new PIN',
      _Step.confirmNew => 'Confirm your new PIN',
    };

    return Scaffold(
      appBar: AppBar(title: const Text('Change PIN')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 24),
              Pinput(
                key: ValueKey(_step),
                controller: _ctrl,
                length: _pinLength,
                obscureText: true,
                enabled: !_busy,
                defaultPinTheme: defaultPin,
                focusedPinTheme: defaultPin.copyWith(
                  decoration: defaultPin.decoration!.copyWith(
                    border: Border.all(color: theme.colorScheme.primary, width: 1.6),
                  ),
                ),
                onCompleted: _onComplete,
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                Text(_error!, style: const TextStyle(color: AppPalette.danger, fontSize: 13)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
