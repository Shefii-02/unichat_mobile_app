import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';
import 'package:unichat_mobile_app/core/storage/secure_storage.dart';

String _hashPin(String pin) => sha256.convert(utf8.encode('flowexa-app-lock::$pin')).toString();

class AppLockState {
  const AppLockState({
    required this.loaded,
    required this.hasMpin,
    required this.biometricEnabled,
    required this.biometricAvailable,
    required this.locked,
    this.justAuthenticated = false,
  });

  /// Whether the device even has usable biometrics enrolled — hide the toggle if not.
  final bool biometricAvailable;
  final bool loaded;
  final bool hasMpin;
  final bool biometricEnabled;
  /// True until the app-lock screen (or setup) has been passed for this app session.
  final bool locked;
  /// True right after a fresh device login — the lock/setup screen shown in this state
  /// offers "reset app lock" (skip old-PIN verification) since identity was just proven.
  final bool justAuthenticated;

  AppLockState copyWith({
    bool? loaded,
    bool? hasMpin,
    bool? biometricEnabled,
    bool? biometricAvailable,
    bool? locked,
    bool? justAuthenticated,
  }) =>
      AppLockState(
        loaded: loaded ?? this.loaded,
        hasMpin: hasMpin ?? this.hasMpin,
        biometricEnabled: biometricEnabled ?? this.biometricEnabled,
        biometricAvailable: biometricAvailable ?? this.biometricAvailable,
        locked: locked ?? this.locked,
        justAuthenticated: justAuthenticated ?? this.justAuthenticated,
      );

  static const initial = AppLockState(
    loaded: false, hasMpin: false, biometricEnabled: false, biometricAvailable: false, locked: false,
  );
}

/// Device-level app-lock: fully opt-in — the user turns it on themselves from Settings
/// (see `_AppLockTile`), never forced during first-time setup. Once an MPIN exists it's
/// mandatory to unlock with (biometric is only ever a shortcut on top of it, never a
/// replacement). Not tied to any one account: logging out keeps the MPIN on this phone (see
/// SecureStorageService.clearAll), so logging back in offers to reuse it instead of forcing
/// setup again every time.
class AppLockNotifier extends Notifier<AppLockState> {
  final _localAuth = LocalAuthentication();

  @override
  AppLockState build() {
    Future.microtask(refresh);
    return AppLockState.initial;
  }

  Future<void> refresh() async {
    final hasMpin = await SecureStorageService.hasMpin();
    final biometricEnabled = await SecureStorageService.isBiometricEnabled();
    bool biometricAvailable = false;
    try {
      biometricAvailable = await _localAuth.canCheckBiometrics && await _localAuth.isDeviceSupported();
    } catch (_) {
      biometricAvailable = false;
    }
    state = state.copyWith(
      loaded: true,
      hasMpin: hasMpin,
      biometricEnabled: biometricEnabled && biometricAvailable,
      biometricAvailable: biometricAvailable,
      // Lock only if there's actually an MPIN to unlock — a device that has never set one
      // up (the default, since it's opt-in) has nothing to lock and goes straight in.
      locked: hasMpin,
    );
  }

  /// Call right after a successful device/account login — forces the lock (or setup)
  /// screen once, with the reset shortcut available. Skipped entirely if the user has
  /// explicitly disabled app lock (see [disableMpin]) — otherwise every fresh login would
  /// force PIN setup again, making "disable" in Settings meaningless.
  void requireUnlockAfterLogin() {
    if (!state.hasMpin) return;
    state = state.copyWith(locked: true, justAuthenticated: true);
  }

  /// Call when the app is backgrounded, so resuming re-shows the lock screen.
  void lock() {
    if (state.hasMpin) state = state.copyWith(locked: true, justAuthenticated: false);
  }

  Future<bool> setPin(String pin) async {
    await SecureStorageService.saveMpinHash(_hashPin(pin));
    state = state.copyWith(hasMpin: true, locked: false, justAuthenticated: false);
    return true;
  }

  Future<bool> verifyPin(String pin) async {
    final saved = await SecureStorageService.getMpinHash();
    final ok = saved != null && saved == _hashPin(pin);
    if (ok) state = state.copyWith(locked: false, justAuthenticated: false);
    return ok;
  }

  /// Skips old-PIN verification — only ever offered right after a fresh login
  /// ([AppLockState.justAuthenticated]), since identity was just proven another way.
  Future<bool> resetPin(String newPin) => setPin(newPin);

  Future<bool> authenticateWithBiometric() async {
    if (!state.biometricEnabled) return false;
    try {
      final ok = await _localAuth.authenticate(
        localizedReason: 'Unlock Teamzo',
        options: const AuthenticationOptions(biometricOnly: true, stickyAuth: true),
      );
      if (ok) state = state.copyWith(locked: false, justAuthenticated: false);
      return ok;
    } catch (_) {
      return false;
    }
  }

  /// Turns app lock off entirely — clears the PIN and biometric flag together, since
  /// biometric is only ever a shortcut on top of a PIN, never a standalone lock.
  Future<void> disableMpin() async {
    await SecureStorageService.clearMpin();
    await SecureStorageService.setBiometricEnabled(false);
    state = state.copyWith(hasMpin: false, biometricEnabled: false, locked: false);
  }

  Future<void> setBiometricEnabled(bool enabled) async {
    await SecureStorageService.setBiometricEnabled(enabled);
    state = state.copyWith(biometricEnabled: enabled);
  }

  /// Confirms biometrics actually work on this device before turning the setting on — used
  /// by both first-time setup and the Settings toggle. Returns null on success, or a
  /// human-readable reason it failed — surfaced directly in the UI rather than swallowed,
  /// since a single generic "couldn't verify" message gave no way to tell "no fingerprint
  /// enrolled on this phone" apart from an actual bug.
  Future<String?> enableBiometric() async {
    try {
      final ok = await _localAuth.authenticate(
        localizedReason: 'Confirm biometric unlock for Teamzo',
        options: const AuthenticationOptions(biometricOnly: true, stickyAuth: true),
      );
      if (!ok) return 'Biometric check was cancelled.';
      await setBiometricEnabled(true);
      return null;
    } on PlatformException catch (e) {
      return switch (e.code) {
        'NotEnrolled' =>
          'No fingerprint or face is enrolled on this device yet — add one in your phone\'s Settings app, then try again.',
        'NotAvailable' => 'Biometric hardware is not available on this device.',
        'PasscodeNotSet' => 'Set a device screen-lock PIN/pattern/password first, then try again.',
        'LockedOut' || 'PermanentlyLockedOut' =>
          'Too many failed attempts — biometrics are temporarily locked on this device. Try again later.',
        _ => e.message ?? 'Could not verify biometrics (${e.code}).',
      };
    } catch (e) {
      return 'Could not verify biometrics: $e';
    }
  }
}

final appLockProvider = NotifierProvider<AppLockNotifier, AppLockState>(AppLockNotifier.new);
