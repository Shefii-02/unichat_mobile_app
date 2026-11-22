import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unichat_mobile_app/core/storage/local_storage.dart';
import 'package:unichat_mobile_app/core/theme/app_theme.dart';
import 'package:unichat_mobile_app/features/auth/data/auth_repository.dart';
import 'package:unichat_mobile_app/features/auth/data/device_auth_repository.dart';
import 'package:unichat_mobile_app/features/auth/presentation/pages/login_page.dart';
import 'package:unichat_mobile_app/features/auth/presentation/providers/auth_provider.dart';

import 'support/fake_api.dart';

const _user = {
  'id': 7, 'name': 'Ann Lee', 'email': 'ann@x.io', 'phone': '9000000001', 'role': {'name': 'counsellor'},
  'company': {'id': 3, 'name': 'Acme', 'slug': 'acme'}, 'permissions': <String>[],
};

const _ticket = 'TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT'; // 40 characters, like the server's

Map<String, dynamic> _limitBody({String token = _ticket, List<Map<String, dynamic>>? devices}) => {
      'error': 'device_limit',
      'message': 'This account is already signed in on 2 phones. Remove one to continue.',
      'max': 2,
      'limit_token': token,
      'devices': devices ?? [
        {'id': 11, 'device_name': 'Ann Pixel', 'platform': 'android', 'last_active_at': DateTime.now().subtract(const Duration(hours: 3)).toIso8601String()},
        {'id': 12, 'device_name': 'Ann iPhone', 'platform': 'ios', 'last_active_at': DateTime.now().subtract(const Duration(days: 2)).toIso8601String()},
      ],
    };

Future<void> _pump(WidgetTester tester, [int steps = 30]) async {
  for (var i = 0; i < steps; i++) { await tester.pump(const Duration(milliseconds: 40)); }
}

void main() {
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    await LocalStorage.init();
  });

  group('AuthRepository.login', () {
    test('sends this phone\'s id with the email + password, and signs in', () async {
      final api = FakeApi((o) => {'data': {'access_token': 'jwt', 'user': _user}})..install();
      final user = await AuthRepository().login(email: 'ann@x.io', password: 'pw');
      expect(user.name, 'Ann Lee');
      final body = api.where('POST', '/auth/login').single.data as Map;
      expect(body['email'], 'ann@x.io');
      expect((body['device_uid'] as String).length, greaterThanOrEqualTo(8), reason: 'the phone registers itself on every sign-in');
      expect(body.keys, containsAll(['device_name', 'platform', 'app_version']));
      expect(LocalStorage.getString(LocalStorage.kDeviceUid), body['device_uid'], reason: 'the same id is reused next time, not a new one');
    });

    test('over the phone limit: throws a DeviceLimitException carrying the phones and the ticket', () async {
      FakeApi((o) => FakeReply(409, _limitBody()))..install();
      await expectLater(
        AuthRepository().login(email: 'ann@x.io', password: 'pw'),
        throwsA(isA<DeviceLimitException>()
            .having((e) => e.devices.map((d) => d.id), 'device ids', [11, 12])
            .having((e) => e.limitToken, 'ticket', _ticket)
            .having((e) => e.max, 'max', 2)
            .having((e) => e.message, 'message', contains('Remove one'))),
      );
    });

    test('a wrong password is still an ordinary error, not a device-limit', () async {
      FakeApi((o) => const FakeReply(401, {'message': 'Invalid credentials'}))..install();
      await expectLater(AuthRepository().login(email: 'a@x.io', password: 'bad'), throwsA(isNot(isA<DeviceLimitException>())));
    });

    test('logout keeps the phone\'s own settings (theme, onboarding, device id) and forgets the person', () async {
      FakeApi((o) => {})..install();
      await LocalStorage.setString(LocalStorage.kThemeMode, 'dark');
      await LocalStorage.setBool(LocalStorage.kOnboardingSeen, true);
      await LocalStorage.setString(LocalStorage.kDeviceUid, 'device-uid-1234');
      await LocalStorage.setBool(LocalStorage.kAppLockSetupPromptSeen, true);
      await LocalStorage.setJson(LocalStorage.kUser, {'id': 7});
      await LocalStorage.setString('sticky_notes_v1', 'my private notes');
      await AuthRepository().logout();
      expect(LocalStorage.getString(LocalStorage.kThemeMode), 'dark');
      expect(LocalStorage.getBool(LocalStorage.kOnboardingSeen), isTrue, reason: 'onboarding must not reappear on every logout');
      expect(LocalStorage.getString(LocalStorage.kDeviceUid), 'device-uid-1234', reason: 'a new device id each login would use up the phone limit');
      expect(LocalStorage.getBool(LocalStorage.kAppLockSetupPromptSeen), isTrue);
      expect(LocalStorage.getJson(LocalStorage.kUser), isNull);
      expect(LocalStorage.getString('sticky_notes_v1'), isNull, reason: 'the next person on this phone must not see the last one\'s notes');
    });
  });

  group('email login screen: device limit', () {
    Future<(ProviderContainer, FakeApi, List<String>)> open(WidgetTester tester, dynamic Function(RequestOptions o, int loginCalls) handler) async {
      var loginCalls = 0;
      final log = <String>[];
      final api = FakeApi((o) {
        log.add('${o.method} ${o.path}');
        if (o.path == '/auth/login') loginCalls++;
        return handler(o, loginCalls);
      })..install();
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: AppTheme.light, home: const LoginPage()),
      ));
      await tester.enterText(find.byType(TextFormField).at(0), 'ann@x.io');
      await tester.enterText(find.byType(TextFormField).at(1), 'secret123');
      await tester.tap(find.text('Login'));
      await _pump(tester);
      return (container, api, log);
    }

    testWidgets('under the limit: signs in at once, no sheet', (tester) async {
      final (c, _, _) = await open(tester, (o, n) => o.path == '/auth/login' ? {'data': {'access_token': 'jwt', 'user': _user}} : {});
      expect(find.text('Device limit reached'), findsNothing);
      expect(c.read(authProvider).value?.name, 'Ann Lee');
    });

    testWidgets('at the limit: shows the phones, Remove frees one, repeats the sign-in and lands signed in', (tester) async {
      final (c, api, log) = await open(tester, (o, n) {
        if (o.path == '/auth/login') return n == 1 ? FakeReply(409, _limitBody()) : {'data': {'access_token': 'jwt', 'user': _user}};
        if (o.path == '/auth/mobile-devices/remove') return {'message': 'ok', 'devices': <dynamic>[]};
        return {};
      });
      expect(find.text('Device limit reached'), findsOneWidget);
      expect(find.text('Ann Pixel'), findsOneWidget);
      expect(find.text('Ann iPhone'), findsOneWidget);
      expect(find.byKey(const ValueKey('limit-message')), findsOneWidget);
      expect(c.read(authProvider).value, isNull, reason: 'not signed in while the limit is unresolved');

      await tester.tap(find.byKey(const ValueKey('remove-11')));
      await _pump(tester);

      expect(log, ['POST /auth/login', 'POST /auth/mobile-devices/remove', 'POST /auth/login'], reason: 'remove, then the SAME sign-in again');
      final removeCall = api.where('POST', '/auth/mobile-devices/remove').single.data as Map;
      expect(removeCall, {'limit_token': _ticket, 'device_id': 11});
      final second = api.where('POST', '/auth/login').last.data as Map;
      expect(second['email'], 'ann@x.io');
      expect(second['password'], 'secret123', reason: 'no need to type the password again');
      expect(find.text('Device limit reached'), findsNothing, reason: 'the sheet closes');
      expect(c.read(authProvider).value?.name, 'Ann Lee', reason: 'and the person is in — the router then takes them to the home screen');
    });

    testWidgets('still over the limit after one removal: the sheet refreshes with the new list and ticket', (tester) async {
      final (c, api, _) = await open(tester, (o, n) {
        if (o.path == '/auth/login') {
          if (n == 1) return FakeReply(409, _limitBody());
          if (n == 2) return FakeReply(409, _limitBody(token: 'N' * 40, devices: [
            {'id': 12, 'device_name': 'Ann iPhone', 'platform': 'ios'},
            {'id': 13, 'device_name': 'Ann Tablet', 'platform': 'android'},
          ]));
          return {'data': {'access_token': 'jwt', 'user': _user}};
        }
        return {'devices': <dynamic>[]};
      });
      await tester.tap(find.byKey(const ValueKey('remove-11')));
      await _pump(tester);
      expect(find.text('Device limit reached'), findsOneWidget);
      expect(find.text('Ann Pixel'), findsNothing);
      expect(find.text('Ann Tablet'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('remove-13')));
      await _pump(tester);
      final removes = api.where('POST', '/auth/mobile-devices/remove').toList();
      expect((removes.last.data as Map)['limit_token'], 'N' * 40, reason: 'uses the NEW ticket');
      expect(c.read(authProvider).value?.name, 'Ann Lee');
    });

    testWidgets('removal fails: the message is shown and nothing is signed in', (tester) async {
      final (c, _, _) = await open(tester, (o, n) {
        if (o.path == '/auth/login') return FakeReply(409, _limitBody());
        return const FakeReply(410, {'message': 'This request expired — sign in again.'});
      });
      await tester.tap(find.byKey(const ValueKey('remove-11')));
      await _pump(tester);
      expect(find.text('This request expired — sign in again.'), findsOneWidget);
      expect(find.text('Device limit reached'), findsOneWidget);
      expect(c.read(authProvider).value, isNull);
    });

    testWidgets('Cancel closes the sheet and stays signed out', (tester) async {
      final (c, api, _) = await open(tester, (o, n) => o.path == '/auth/login' ? FakeReply(409, _limitBody()) : {});
      await tester.tap(find.text('Cancel'));
      await _pump(tester, 15);
      expect(find.text('Device limit reached'), findsNothing);
      expect(c.read(authProvider).value, isNull);
      expect(api.where('POST', '/auth/mobile-devices/remove'), isEmpty);
    });

    testWidgets('wrong password: a clear message, no sheet', (tester) async {
      final (_, _, _) = await open(tester, (o, n) => const FakeReply(401, {'message': 'Invalid credentials'}));
      expect(find.text('Invalid email or password.'), findsOneWidget);
      expect(find.text('Device limit reached'), findsNothing);
    });
  });
}
