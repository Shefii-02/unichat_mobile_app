import 'dart:ui';

import 'package:flutter/material.dart';

/// Full-screen blurred "please wait" overlay shown while an attendance punch
/// is being checked/submitted. Call [show] and later [hide] (idempotent).
class BlurLoadingOverlay {
  BlurLoadingOverlay._(this._context);
  final BuildContext _context;
  bool _open = true;

  static BlurLoadingOverlay show(BuildContext context, {String message = 'Please wait…'}) {
    final o = BlurLoadingOverlay._(context);
    showGeneralDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      barrierColor: Colors.black26,
      transitionDuration: const Duration(milliseconds: 150),
      pageBuilder: (_, __, ___) => PopScope(
        canPop: false,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 22),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(width: 36, height: 36, child: CircularProgressIndicator(strokeWidth: 3)),
                  const SizedBox(height: 14),
                  Text(message,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600, decoration: TextDecoration.none)),
                ],
              ),
            ),
          ),
        ),
      ),
    ).whenComplete(() => o._open = false);
    return o;
  }

  void hide() {
    if (!_open) return;
    _open = false;
    if (_context.mounted) Navigator.of(_context, rootNavigator: true).pop();
  }
}
