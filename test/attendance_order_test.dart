import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:unichat_mobile_app/core/theme/app_theme.dart';
import 'package:unichat_mobile_app/features/attendance/attendance_actions.dart';

import 'support/fake_api.dart';

/// The clock-in order the company wants: swipe → SELFIE camera first → THEN the location / office-radius check → a reason only if the
/// check says one is needed → submit (and the app goes home).
Position _at(double lat, double lng) => Position(
      latitude: lat, longitude: lng, timestamp: DateTime(2026, 11, 23, 9), accuracy: 5, altitude: 0, altitudeAccuracy: 0,
      heading: 0, headingAccuracy: 0, speed: 0, speedAccuracy: 0,
    );

class _Run {
  _Run({this.settings = const {}, this.check = const {}, this.fix = const []});
  final Map<String, dynamic> settings;
  final Map<String, dynamic> check;
  /// What each location attempt returns, in order (null = no fix).
  final List<Position?> fix;
  final events = <String>[];
  bool? result;
  // a real 1×1 PNG: the review sheet shows the photo, so it has to be a valid image
  late final File photo = File('${Directory.systemTemp.path}/selfie_test.png')
    ..writeAsBytesSync(base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=='));
  late final FakeApi api = FakeApi((o) {
    if (o.path == '/hr/attendance/me') return {'settings': settings};
    if (o.path == '/hr/attendance/precheck') { events.add('precheck'); return check; }
    if (o.path.startsWith('/hr/attendance/')) { events.add('submit'); return {'data': {}}; }
    return {};
  })..install();

  Map<String, dynamic> submitted() => {for (final f in (api.where('POST', '/hr/attendance/clock-in').last.data as FormData).fields) f.key: f.value};
  bool submittedSelfie() => (api.where('POST', '/hr/attendance/clock-in').last.data as FormData).files.any((f) => f.key == 'selfie');

  Future<void> start(WidgetTester tester, {String action = 'clock_in'}) async {
    api;
    var attempt = 0;
    selfieCaptureOverride = (context) async { events.add('selfie'); return XFile(photo.path); };
    positionOverride = (limit) async { events.add('location'); final p = attempt < fix.length ? fix[attempt] : null; attempt++; return p; };
    addTearDown(() { selfieCaptureOverride = null; positionOverride = null; });
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: Builder(builder: (context) => Scaffold(body: Center(child: ElevatedButton(
      onPressed: () async => result = await attendanceAction(context, action: action, settings: settings),
      child: const Text('Swipe'),
    ))))));
    await tester.tap(find.text('Swipe'));
    await _pump(tester);
  }
}

/// Attaching the photo reads a real file, which needs REAL time (a simulated clock never completes file IO) — so alternate both.
Future<void> _pump(WidgetTester tester, [int steps = 20]) async {
  for (var i = 0; i < steps; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 15)));
    await tester.pump(const Duration(milliseconds: 40));
  }
}

void main() {
  test('minutes read as hours:minutes', () {
    expect(formatDelay(0), '0:00'); expect(formatDelay(45), '0:45'); expect(formatDelay(60), '1:00');
    expect(formatDelay(687), '11:27'); expect(formatDelay(135), '2:15');
    expect(delayLabel({'late_minutes': 687, 'delay_kind': 'late'}), '11:27 min late');
    expect(delayLabel({'late_minutes': 30, 'delay_kind': 'early_leave'}), '0:30 min before time');
    expect(delayLabel({'late_minutes': 10, 'delay_kind': null}), isNull, reason: 'inside the grace minutes is not a delay');
    expect(delayLabel({'late_minutes': 687, 'note_optional': true}), '11:27 min late', reason: 'an older server sends no delay_kind');
    expect(humanizeMinutes("You're 687 min late — you can add a reason (optional)."), "You're 11:27 min late — you can add a reason (optional).");
  });

  setUp(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('flutter.baseflow.com/geolocator'), (call) async => call.method == 'isLocationServiceEnabled' ? false : null));

  const needsBoth = {'selfie_required_clock_in': true, 'geo_required': true};

  testWidgets('selfie first, THEN location, then the check, then submit — in that order', (tester) async {
    final r = _Run(settings: needsBoth, fix: [_at(10.0, 76.0)], check: {'radius_reason_needed': false, 'distance_m': 12, 'allowed_m': 100});
    await r.start(tester);
    expect(r.events, ['selfie', 'location', 'precheck', 'submit'], reason: 'the camera must open before any location check');
    expect(r.result, isTrue);
  });

  testWidgets('inside the office radius and on time: no reason is asked — it submits with the photo and the location and goes straight on', (tester) async {
    final r = _Run(settings: needsBoth, fix: [_at(10.0, 76.0)], check: {'radius_reason_needed': false, 'note_required': false, 'note_optional': false});
    await r.start(tester);
    expect(find.byKey(const ValueKey('reason-field')), findsNothing);
    final f = r.submitted();
    expect(f['lat'], '10.0'); expect(f['lng'], '76.0'); expect(r.submittedSelfie(), isTrue);
    expect(f.containsKey('radius_reason'), isFalse); expect(f.containsKey('note'), isFalse);
    expect(r.result, isTrue);
  });

  testWidgets('outside the office radius: the alert and a REQUIRED reason are asked after the check, then it submits with that reason', (tester) async {
    final r = _Run(settings: needsBoth, fix: [_at(10.05, 76.0)], check: {'radius_reason_needed': true, 'radius_message': "You're 5560 m from the office (allowed: 100 m)."});
    await r.start(tester);
    expect(r.events, ['selfie', 'location', 'precheck'], reason: 'nothing is submitted until the reason is given');
    expect(find.byKey(const ValueKey('radius-alert')), findsOneWidget);
    expect(find.textContaining('5560 m from the office'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('reason-field')), 'Client visit');
    await tester.tap(find.byKey(const ValueKey('punch-submit')));
    await _pump(tester);
    expect(r.events.last, 'submit');
    expect(r.submitted()['radius_reason'], 'Client visit');
    expect(r.submittedSelfie(), isTrue, reason: 'the photo is kept and sent');
    expect(r.result, isTrue);
  });

  testWidgets('late + the company wants a reason: asked after the location check; a late reason that is OFF is never asked', (tester) async {
    final late = _Run(settings: needsBoth, fix: [_at(10.0, 76.0)], check: {'note_required': true, 'note_message': 'A reason is required when clocking in late.'});
    await late.start(tester);
    expect(find.text('A reason is required when clocking in late.'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('reason-field')), 'Bus broke down');
    await tester.tap(find.byKey(const ValueKey('punch-submit')));
    await _pump(tester);
    expect(late.submitted()['note'], 'Bus broke down');
  });

  testWidgets('cancelling the selfie stops everything: location is never read, nothing is sent', (tester) async {
    final r = _Run(settings: needsBoth, fix: [_at(10.0, 76.0)]);
    var asked = 0;
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: Builder(builder: (context) => Scaffold(body: ElevatedButton(
      onPressed: () async => r.result = await attendanceAction(context, action: 'clock_in', settings: r.settings), child: const Text('Swipe'))))));
    r.api;
    selfieCaptureOverride = (c) async { r.events.add('selfie'); return null; };   // the person closed the camera
    positionOverride = (l) async { asked++; return _at(10.0, 76.0); };
    addTearDown(() { selfieCaptureOverride = null; positionOverride = null; });
    await tester.tap(find.text('Swipe')); await _pump(tester);
    expect(r.result, isFalse); expect(asked, 0, reason: 'no location check after a cancelled selfie'); expect(r.events, ['selfie']);
  });

  testWidgets('the location cannot be read: "Location required" with Try again — the photo is NOT retaken; Try again succeeds', (tester) async {
    final r = _Run(settings: needsBoth, fix: [null, _at(10.0, 76.0)], check: const {});
    await r.start(tester);
    expect(find.text('Location required'), findsOneWidget);
    expect(r.events, ['selfie', 'location']);
    await tester.tap(find.text('Try again')); await _pump(tester);
    expect(r.events, ['selfie', 'location', 'location', 'precheck', 'submit'], reason: 'only ONE selfie for two location attempts');
    expect(r.result, isTrue);
  });

  testWidgets('the location still cannot be read: Cancel ends the punch, nothing is sent', (tester) async {
    final r = _Run(settings: needsBoth, fix: [null, null]);
    await r.start(tester);
    await tester.tap(find.text('Cancel')); await _pump(tester);
    expect(r.result, isFalse); expect(r.events, ['selfie', 'location']);
  });

  testWidgets('a person with no office radius to respect (work from home): the camera still opens first, and a slow GPS never blocks them', (tester) async {
    final r = _Run(settings: {'selfie_required_clock_in': true, 'geo_required': false, 'geofence_mandatory': true}, fix: [null], check: const {});
    await r.start(tester);
    expect(r.events.first, 'selfie');
    expect(find.text('Location required'), findsNothing);
    expect(r.result, isTrue);
  });

  testWidgets('no selfie needed: it goes straight to the location check', (tester) async {
    final r = _Run(settings: {'geo_required': true}, fix: [_at(10.0, 76.0)], check: const {});
    await r.start(tester);
    expect(r.events, ['location', 'precheck', 'submit']);
  });

  testWidgets('late: the sheet shows the delay as hours and minutes, with roomy bottom padding', (tester) async {
    tester.view.viewPadding = const FakeViewPadding(bottom: 34 * 3);   // a phone's home-indicator inset (3x pixel ratio)
    tester.view.padding = const FakeViewPadding(bottom: 34 * 3);
    addTearDown(() { tester.view.resetViewPadding(); tester.view.resetPadding(); });
    final r = _Run(settings: needsBoth, fix: [_at(10.0, 76.0)], check: {
      'late_minutes': 85, 'delay_kind': 'late', 'note_required': true, 'note_message': 'A reason is required when clocking in late.',
    });
    await r.start(tester);
    expect(find.descendant(of: find.byKey(const ValueKey('delay-badge')), matching: find.text('1:25 min late')), findsOneWidget);
    final gap = tester.getBottomLeft(find.byType(BottomSheet)).dy - tester.getBottomLeft(find.byKey(const ValueKey('punch-submit'))).dy;
    expect(gap, greaterThanOrEqualTo(28 + 34 - 1), reason: 'own 28 + the system inset');
  });

  testWidgets('a 2nd clock-in the same day: the sheet asks WHY, the reason is required, and it is sent as the note', (tester) async {
    final r = _Run(settings: needsBoth, fix: [_at(10.0, 76.0)], check: {
      'note_required': true, 'note_kind': 'new_session', 'late_minutes': 0,
      'note_message': 'You already clocked in earlier today. Why are you clocking in again?',
    });
    await r.start(tester);
    expect(find.text('You already clocked in earlier today. Why are you clocking in again?'), findsOneWidget);
    expect(find.byKey(const ValueKey('delay-badge')), findsNothing, reason: 'a 2nd session is not "late"');
    await tester.tap(find.byKey(const ValueKey('punch-submit'))); await _pump(tester, 4);
    expect(find.text('Please enter a reason'), findsOneWidget);
    expect(r.events.contains('submit'), isFalse);
    await tester.enterText(find.byKey(const ValueKey('reason-field')), 'Came back after the client meeting');
    await tester.tap(find.byKey(const ValueKey('punch-submit'))); await _pump(tester);
    expect(r.submitted()['note'], 'Came back after the client meeting');
  });
}
