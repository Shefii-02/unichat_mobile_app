import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unichat_mobile_app/core/theme/app_theme.dart';
import 'package:unichat_mobile_app/features/attendance/attendance_actions.dart';
import 'package:unichat_mobile_app/features/attendance/selfie_capture_page.dart';
import 'package:unichat_mobile_app/features/attendance/widgets/swipe_action_button.dart';

import 'support/fake_api.dart';

const _geo = MethodChannel('flutter.baseflow.com/geolocator');
const _camera = MethodChannel('plugins.flutter.io/camera');

void _noGps() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
    .setMockMethodCallHandler(_geo, (call) async => call.method == 'isLocationServiceEnabled' ? false : null);

/// A camera that never answers (another app holds it, or a permission prompt was dismissed).
void _cameraHangs() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
    .setMockMethodCallHandler(_camera, (call) => Completer<Object?>().future);

/// Camera plugin answers: `cameras` as the list, or throws the platform error `error`.
void _cameraAnswers({List<Object?> cameras = const [], String? error}) =>
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_camera, (call) async {
      if (error != null) throw PlatformException(code: error, message: 'denied');
      return call.method == 'availableCameras' ? cameras : null;
    });

Future<void> _advance(WidgetTester tester, Duration total, {Duration step = const Duration(milliseconds: 100)}) async {
  for (var t = Duration.zero; t < total; t += step) { await tester.pump(step); }
}

Future<bool?> _punch(WidgetTester tester, Map<String, dynamic> settings, {String action = 'clock_in'}) async {
  bool? result;
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    home: Builder(builder: (context) => Scaffold(body: Center(child: ElevatedButton(
      onPressed: () async => result = await attendanceAction(context, action: action, settings: settings),
      child: const Text('Punch'),
    )))),
  ));
  await tester.tap(find.text('Punch'));
  await tester.pump();
  return result;
}

void main() {
  setUp(() { _noGps(); _cameraAnswers(); });

  group('clock in does not look frozen', () {
    testWidgets('while the latest settings load, a "Getting ready…" overlay is up straight away', (tester) async {
      FakeApi((o) => o.path == '/hr/attendance/me' ? FakeReply(200, {'settings': {}}, delay: const Duration(seconds: 3)) : {})..install();
      await _punch(tester, {});
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Getting ready…'), findsOneWidget, reason: 'the person must see that something is happening');
      await _advance(tester, const Duration(seconds: 4));
      expect(find.text('Getting ready…'), findsNothing, reason: 'and it goes away by itself');
    });

    testWidgets('a very slow server: after 6 seconds it carries on with the settings already on screen and opens the selfie camera screen', (tester) async {
      FakeApi((o) => o.path == '/hr/attendance/me' ? FakeReply(200, {'settings': {}}, delay: const Duration(seconds: 25)) : {})..install();
      await _punch(tester, {'selfie_required_clock_in': true});
      await _advance(tester, const Duration(seconds: 5));
      expect(find.text('📷 Take a selfie'), findsNothing, reason: 'still waiting for the server');
      await _advance(tester, const Duration(seconds: 2));
      expect(find.text('Getting ready…'), findsNothing);
      expect(find.text('📷 Take a selfie'), findsOneWidget, reason: 'it used to wait up to 30 s here with nothing on screen');
      await _advance(tester, const Duration(seconds: 30));   // let the simulated slow answers finish
    });

    testWidgets('settings that arrive in time win: selfie switched off on the server means no selfie screen', (tester) async {
      FakeApi((o) => o.path == '/hr/attendance/me' ? {'settings': {'selfie_required_clock_in': false}} : o.path == '/hr/attendance/precheck' ? {} : {'data': {}})..install();
      bool? done;
      await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: Builder(builder: (c) => Scaffold(body: ElevatedButton(
        onPressed: () async => done = await attendanceAction(c, action: 'clock_in', settings: {'selfie_required_clock_in': true}), child: const Text('Punch'))))));
      await tester.tap(find.text('Punch'));
      await _advance(tester, const Duration(seconds: 2));
      expect(find.text('📷 Take a selfie'), findsNothing);
      expect(done, isTrue);
    });

    testWidgets('a slow precheck does not hold the punch: after 8 seconds it goes ahead and submits', (tester) async {
      final api = FakeApi((o) {
        if (o.path == '/hr/attendance/me') return {'settings': {}};
        if (o.path == '/hr/attendance/precheck') return FakeReply(200, {}, delay: const Duration(seconds: 40));
        return {'data': {}};
      })..install();
      bool? done;
      await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: Builder(builder: (c) => Scaffold(body: ElevatedButton(
        onPressed: () async => done = await attendanceAction(c, action: 'clock_in', settings: const {}), child: const Text('Punch'))))));
      await tester.tap(find.text('Punch'));
      await _advance(tester, const Duration(seconds: 7));
      expect(find.text('Validating…'), findsOneWidget);
      expect(done, isNull);
      await _advance(tester, const Duration(seconds: 3));
      expect(done, isTrue, reason: 'the real submit makes the same checks, so waiting 40 s for the dry run is pointless');
      expect(api.where('POST', '/hr/attendance/clock-in'), hasLength(1));
      await _advance(tester, const Duration(seconds: 40));   // let the simulated slow answer finish
    });
  });

  group('selfie screen', () {
    Future<void> openSelfie(WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: Builder(builder: (c) => Scaffold(body: ElevatedButton(
        onPressed: () => showDialog(context: c, builder: (_) => const SelfieCapturePage()), child: const Text('Open'))))));
      await tester.tap(find.text('Open'));
      await tester.pump();
    }

    testWidgets('a camera that never opens: after 12 seconds it explains and offers "Try again" (it used to spin forever)', (tester) async {
      _cameraHangs();
      await openSelfie(tester);
      await _advance(tester, const Duration(seconds: 6));
      expect(find.byType(CircularProgressIndicator), findsOneWidget, reason: 'still trying');
      await _advance(tester, const Duration(seconds: 7));
      expect(find.textContaining('taking too long to open'), findsOneWidget);
      expect(find.byKey(const ValueKey('selfie-retry')), findsOneWidget);
      expect(find.byKey(const ValueKey('selfie-capture')), findsNothing, reason: 'no dead Capture button');
    });

    testWidgets('"Try again" retries from the start', (tester) async {
      _cameraHangs();
      await openSelfie(tester);
      await _advance(tester, const Duration(seconds: 13));
      await tester.tap(find.byKey(const ValueKey('selfie-retry')));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget, reason: 'spinner again while retrying');
      expect(find.textContaining('taking too long'), findsNothing);
      await _advance(tester, const Duration(seconds: 13));
      expect(find.textContaining('taking too long to open'), findsOneWidget);
    });

    testWidgets('the dialog lays out with the real app theme (its buttons used to get an infinite width, so it never appeared)', (tester) async {
      _cameraAnswers();   // no camera on the device
      await openSelfie(tester);
      await _advance(tester, const Duration(seconds: 1));
      expect(tester.takeException(), isNull, reason: 'the full-width FilledButton theme must not break the dialog');
      expect(find.text('📷 Take a selfie'), findsOneWidget);
      expect(find.textContaining('No camera available'), findsOneWidget);
      final retry = tester.getSize(find.byKey(const ValueKey('selfie-retry')));
      expect(retry.width, lessThan(300), reason: 'a normal button, not stretched to infinity');
    });

    testWidgets('permission denied: a clear message and "Try again"; Cancel closes the screen', (tester) async {
      _cameraAnswers(error: 'CameraAccessDenied');
      await openSelfie(tester);
      await _advance(tester, const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
      expect(find.textContaining('Could not open the camera'), findsOneWidget);
      expect(find.byKey(const ValueKey('selfie-retry')), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await _advance(tester, const Duration(milliseconds: 400));
      expect(find.byType(SelfieCapturePage), findsNothing);
    });
  });

  group('swipe button', () {
    testWidgets('after the swipe it shows "Working…" with a spinner until the punch finishes, then resets', (tester) async {
      final done = Completer<void>();
      await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: Scaffold(body: Padding(
        padding: const EdgeInsets.all(16),
        child: SwipeActionButton(label: 'Clock in', icon: Icons.login_rounded, color: Colors.indigo, onSwipe: () => done.future),
      ))));
      expect(find.textContaining('Swipe to clock in'), findsOneWidget);
      await tester.drag(find.byIcon(Icons.login_rounded), const Offset(900, 0));
      await tester.pump();
      expect(find.text('Working…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      done.complete();
      await _advance(tester, const Duration(seconds: 1));
      expect(find.text('Working…'), findsNothing);
      expect(find.textContaining('Swipe to clock in'), findsOneWidget, reason: 'ready for another try (e.g. after cancelling the selfie)');
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('a punch that throws still resets the button (never stuck)', (tester) async {
      await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: Scaffold(body: Padding(
        padding: const EdgeInsets.all(16),
        child: SwipeActionButton(label: 'Clock in', icon: Icons.login_rounded, color: Colors.indigo, onSwipe: () async => throw StateError('boom')),
      ))));
      await tester.drag(find.byIcon(Icons.login_rounded), const Offset(900, 0));
      await _advance(tester, const Duration(seconds: 1));
      expect(tester.takeException(), isA<StateError>());
      expect(find.textContaining('Swipe to clock in'), findsOneWidget);
    });
  });
}
