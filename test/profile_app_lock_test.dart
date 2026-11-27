import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unichat_mobile_app/core/storage/local_storage.dart';
import 'package:unichat_mobile_app/core/storage/secure_storage.dart';
import 'package:unichat_mobile_app/core/theme/app_theme.dart';
import 'package:unichat_mobile_app/features/app_lock/app_lock_provider.dart';
import 'package:unichat_mobile_app/features/settings/presentation/pages/settings_page.dart';

import 'support/fake_api.dart';

Future<void> _pump(WidgetTester tester, [int steps = 20]) async {
  for (var i = 0; i < steps; i++) { await tester.pump(const Duration(milliseconds: 40)); }
}

/// The App Lock PIN switch lives in Settings → Security (it used to be duplicated on Profile).
final _lockFinder = find.descendant(of: find.widgetWithText(SwitchListTile, 'App Lock PIN'), matching: find.byType(Switch));
Switch _lockSwitch(WidgetTester tester) => tester.widget<Switch>(_lockFinder);

/// No biometric hardware in a unit test: answer the local_auth plugin as a phone without any.
void _noBiometrics() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/local_auth'),
    (call) async => switch (call.method) { 'getAvailableBiometrics' => <String>[], _ => false },
  );
}

void main() {
  late ProviderContainer container;
  setUp(_noBiometrics);

  Future<void> open(WidgetTester tester, {Map<String, String> secure = const {}}) async {
    // Settings is a long list and builds lazily — a tall screen keeps the Security section on it
    tester.view.physicalSize = const Size(800, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    FlutterSecureStorage.setMockInitialValues({...secure});   // must be modifiable: saving a PIN writes to it
    SharedPreferences.setMockInitialValues({});
    await LocalStorage.init();
    FakeApi((o) => {})..install();
    container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: AppTheme.light, home: const SettingsPage()),
    ));
    await _pump(tester);
  }

  testWidgets('Settings has an "App Lock PIN" switch (off when no PIN was set)', (tester) async {
    await open(tester);
    expect(find.text('App Lock PIN'), findsOneWidget);
    expect(_lockSwitch(tester).value, isFalse);
  });

  testWidgets('turn it on from Settings: create + confirm a PIN, then the switch is on and a PIN is saved', (tester) async {
    await open(tester);
    await tester.tap(_lockFinder);
    await _pump(tester);
    expect(find.text('Create your app lock PIN'), findsOneWidget);

    await tester.enterText(find.byType(EditableText), '4821');
    await _pump(tester);
    expect(find.text('Confirm your PIN'), findsOneWidget);
    await tester.enterText(find.byType(EditableText), '4821');
    await _pump(tester, 30);

    expect(container.read(appLockProvider).hasMpin, isTrue);
    expect(await SecureStorageService.hasMpin(), isTrue);
    expect(_lockSwitch(tester).value, isTrue);
  });

  testWidgets('a mismatching confirmation is refused and nothing is saved', (tester) async {
    await open(tester);
    await tester.tap(_lockFinder);
    await _pump(tester);
    await tester.enterText(find.byType(EditableText), '1111');
    await _pump(tester);
    await tester.enterText(find.byType(EditableText), '2222');
    await _pump(tester);
    expect(find.text("PINs don't match — try again."), findsOneWidget);
    expect(container.read(appLockProvider).hasMpin, isFalse);
  });

  testWidgets('turn it off from Settings: asks first, then the PIN is removed (and biometric with it)', (tester) async {
    await open(tester, secure: {'app_lock_mpin_hash': 'somehash', 'app_lock_biometric_enabled': 'true'});
    await container.read(appLockProvider.notifier).refresh();
    await _pump(tester);
    expect(_lockSwitch(tester).value, isTrue);

    await tester.tap(_lockFinder);
    await _pump(tester);
    expect(find.text('Turn off App Lock PIN?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await _pump(tester);
    expect(container.read(appLockProvider).hasMpin, isTrue, reason: 'cancelling keeps the lock');

    await tester.tap(_lockFinder);
    await _pump(tester);
    await tester.tap(find.text('Turn off'));
    await _pump(tester);
    expect(container.read(appLockProvider).hasMpin, isFalse);
    expect(await SecureStorageService.hasMpin(), isFalse);
    expect(await SecureStorageService.isBiometricEnabled(), isFalse);
    expect(_lockSwitch(tester).value, isFalse);
  });

  testWidgets('with no PIN the app never locks (skipping the prompt really means "no lock")', (tester) async {
    await open(tester);
    await container.read(appLockProvider.notifier).refresh();
    final s = container.read(appLockProvider);
    expect(s.hasMpin, isFalse);
    expect(s.locked, isFalse);
    container.read(appLockProvider.notifier).lock();          // app sent to the background
    container.read(appLockProvider.notifier).requireUnlockAfterLogin();
    expect(container.read(appLockProvider).locked, isFalse, reason: 'nothing to unlock with');
  });

  testWidgets('with a PIN the app locks when backgrounded, and unlocks with the right PIN only', (tester) async {
    await open(tester);
    final n = container.read(appLockProvider.notifier);
    await n.setPin('4821');
    n.lock();
    expect(container.read(appLockProvider).locked, isTrue);
    expect(await n.verifyPin('0000'), isFalse);
    expect(container.read(appLockProvider).locked, isTrue);
    expect(await n.verifyPin('4821'), isTrue);
    expect(container.read(appLockProvider).locked, isFalse);
  });
}
