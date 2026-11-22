import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unichat_mobile_app/core/theme/app_theme.dart';
import 'package:unichat_mobile_app/features/attendance/attendance_actions.dart';

import 'support/fake_api.dart';

/// Drives the real [attendanceAction] (everything except the camera and GPS plugins) against a fake server.
class _Harness {
  _Harness({this.settings = const {}, this.check = const {}, this.me = const {}, this.submit});

  final Map<String, dynamic> settings;
  Map<String, dynamic> check;
  final Map<String, dynamic> me;
  final dynamic Function(RequestOptions o)? submit;
  bool? result;
  late final FakeApi api = FakeApi((o) {
    if (o.path == '/hr/attendance/me') return {'settings': settings, ...me};
    if (o.path == '/hr/attendance/precheck') return check;
    if (o.path.startsWith('/hr/attendance/')) return submit != null ? submit!(o) : {'data': {'ok': true}};
    return {};
  })..install();

  Iterable<RequestOptions> posts(String path) => api.where('POST', path);
  Map<String, dynamic> fields(String path) => {for (final f in (posts(path).last.data as FormData).fields) f.key: f.value};

  Future<void> start(WidgetTester tester, {String action = 'clock_in'}) async {
    api; // install
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async => result = await attendanceAction(context, action: action, settings: settings),
              child: const Text('Punch'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Punch'));
    await _pump(tester);
  }
}

/// pumpAndSettle never ends while a spinner is up, so advance time in small steps instead.
Future<void> _pump(WidgetTester tester, [int steps = 25]) async {
  for (var i = 0; i < steps; i++) {
    await tester.pump(const Duration(milliseconds: 40));
  }
}

/// The GPS plugin does not exist in a unit test: answer as a phone with location services switched off (so no fix, instantly).
void _noGps() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('flutter.baseflow.com/geolocator'),
    (call) async => call.method == 'isLocationServiceEnabled' ? false : null,
  );
}

void main() {
  setUp(_noGps);

  testWidgets('on time, inside the radius: goes straight through — no reason box, no sheet — and says it came from the phone', (tester) async {
    final h = _Harness(check: {'radius_reason_needed': false, 'note_required': false, 'note_optional': false});
    await h.start(tester);
    expect(h.result, isTrue);
    expect(find.byKey(const ValueKey('reason-field')), findsNothing);
    expect(find.text('Confirm clock in'), findsNothing);
    final f = h.fields('/hr/attendance/clock-in');
    expect(f['source'], 'mobile', reason: 'the attendance row used to be recorded as "web"');
    expect(f.containsKey('note'), isFalse);
    expect(f.containsKey('radius_reason'), isFalse);
  });

  testWidgets('late and the company turned the late reason OFF: goes straight through too', (tester) async {
    final h = _Harness(check: {'late_minutes': 75, 'late_note_mode': 'off', 'note_required': false, 'note_optional': false});
    await h.start(tester);
    expect(h.result, isTrue);
    expect(find.byKey(const ValueKey('reason-field')), findsNothing);
  });

  testWidgets('late reason REQUIRED: the sheet asks, refuses an empty reason, and sends the typed one', (tester) async {
    final h = _Harness(check: {
      'late_minutes': 75, 'late_note_mode': 'required', 'note_required': true, 'note_message': 'A reason is required when clocking in late.',
    });
    await h.start(tester);
    expect(find.byKey(const ValueKey('reason-field')), findsOneWidget);
    expect(find.text('A reason is required when clocking in late.'), findsOneWidget);
    expect(find.text('Reason (required)'), findsOneWidget);
    expect(find.byKey(const ValueKey('radius-alert')), findsNothing, reason: 'no geo alert when inside the radius');

    await tester.tap(find.byKey(const ValueKey('punch-submit')));
    await _pump(tester, 5);
    expect(find.text('Please enter a reason'), findsOneWidget);
    expect(h.posts('/hr/attendance/clock-in'), isEmpty, reason: 'nothing is sent without the reason');

    await tester.enterText(find.byKey(const ValueKey('reason-field')), 'Bus broke down');
    await tester.tap(find.byKey(const ValueKey('punch-submit')));
    await _pump(tester);
    expect(h.result, isTrue);
    expect(h.fields('/hr/attendance/clock-in')['note'], 'Bus broke down');
  });

  testWidgets('late reason OPTIONAL: asked, but can be skipped', (tester) async {
    final h = _Harness(check: {'late_minutes': 20, 'late_note_mode': 'optional', 'note_optional': true, 'note_message': "You're 20 min late — you can add a reason (optional)."});
    await h.start(tester);
    expect(find.text('Reason for being late (optional)'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('punch-submit')));
    await _pump(tester);
    expect(h.result, isTrue);
    expect(h.fields('/hr/attendance/clock-in').containsKey('note'), isFalse);
  });

  testWidgets('outside the office radius: a red alert with the distance, a required reason, sent as radius_reason', (tester) async {
    final h = _Harness(check: {
      'radius_reason_needed': true, 'radius_message': "You're 5560 m from the office (allowed: 100 m).", 'distance_m': 5560, 'allowed_m': 100,
    });
    await h.start(tester);
    expect(find.byKey(const ValueKey('radius-alert')), findsOneWidget);
    expect(find.textContaining("You're 5560 m from the office (allowed: 100 m)."), findsOneWidget);
    expect(find.textContaining('Add a reason to continue'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('punch-submit')));
    await _pump(tester, 5);
    expect(find.text('Please enter a reason'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('reason-field')), 'Client visit');
    await tester.tap(find.byKey(const ValueKey('punch-submit')));
    await _pump(tester);
    expect(h.result, isTrue);
    final f = h.fields('/hr/attendance/clock-in');
    expect(f['radius_reason'], 'Client visit');
    expect(f.containsKey('note'), isFalse, reason: 'a geo reason is not a late note');
  });

  testWidgets('Cancel on the sheet cancels the punch and sends nothing', (tester) async {
    final h = _Harness(check: {'note_required': true, 'note_message': 'A reason is required when clocking in late.'});
    await h.start(tester);
    await tester.tap(find.text('Cancel'));
    await _pump(tester, 10);
    expect(h.result, isFalse);
    expect(h.posts('/hr/attendance/clock-in'), isEmpty);
  });

  testWidgets('location required for this person but no GPS fix: a "Location required" dialog, nothing is sent', (tester) async {
    final h = _Harness(settings: {'geo_required': true, 'geofence_mandatory': true});
    await h.start(tester);
    expect(find.text('Location required'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await _pump(tester, 10);
    expect(h.result, isFalse);
    expect(h.posts('/hr/attendance/clock-in'), isEmpty);
  });

  testWidgets('company enforces the radius but THIS person works from home: no location block (it used to stop them)', (tester) async {
    final h = _Harness(settings: {'geo_required': false, 'geofence_mandatory': true}, check: const {});
    await h.start(tester);
    expect(find.text('Location required'), findsNothing);
    expect(h.result, isTrue);
  });

  testWidgets('the server asks for the reason on submit (precheck was unreachable): the app asks and retries', (tester) async {
    var calls = 0;
    final h = _Harness(
      check: const {},
      submit: (o) {
        calls++;
        return calls == 1
            ? const FakeReply(422, {'errors': {'note': ['A reason is required when clocking in late.']}})
            : {'data': {'ok': true}};
      },
    );
    await h.start(tester);
    expect(find.text('Reason needed'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Traffic');
    await tester.tap(find.text('Submit'));
    await _pump(tester);
    expect(h.result, isTrue);
    expect(calls, 2);
    expect(h.fields('/hr/attendance/clock-in')['note'], 'Traffic');
  });

  testWidgets('a server error is shown, not swallowed, and the punch is reported as not done', (tester) async {
    final h = _Harness(check: const {}, submit: (o) => const FakeReply(422, {'errors': {'clock_in': ["You're already clocked in."]}, 'message': "You're already clocked in."}));
    await h.start(tester);
    expect(h.result, isFalse);
    expect(find.textContaining('already clocked in'), findsOneWidget);
  });

  group('taking a break', () {
    final types = {
      'break_types': [
        {'id': 1, 'name': 'Tea', 'max_minutes': 10, 'daily_limit': 2, 'is_active': true},
        {'id': 2, 'name': 'Lunch', 'max_minutes': 45, 'daily_limit': 1, 'is_active': true},
      ],
      'today': {'breaks': [{'break_type_id': 2}]},
    };

    testWidgets('asks which break and sends the chosen type; a used-up type cannot be picked', (tester) async {
      final h = _Harness(me: types, check: const {});
      await h.start(tester, action: 'break_start');
      expect(find.text('Which break?'), findsOneWidget);
      expect(find.text('Tea'), findsOneWidget);
      expect(find.text('Daily limit reached'), findsOneWidget, reason: 'lunch (1 per day) was already taken');

      await tester.tap(find.text('Lunch'));
      await _pump(tester, 5);
      expect(find.text('Which break?'), findsOneWidget, reason: 'tapping a used-up type does nothing');

      await tester.tap(find.byKey(const ValueKey('break-type-1')));
      await _pump(tester);
      expect(h.result, isTrue);
      expect(h.fields('/hr/attendance/break/start')['break_type_id'], '1');
    });

    testWidgets('closing the picker cancels the break', (tester) async {
      final h = _Harness(me: types, check: const {});
      await h.start(tester, action: 'break_start');
      await tester.tapAt(const Offset(10, 10)); // tap outside the sheet
      await _pump(tester, 10);
      expect(h.result, isFalse);
      expect(h.posts('/hr/attendance/break/start'), isEmpty);
    });

    testWidgets('no break types defined: no question, the break just starts', (tester) async {
      final h = _Harness(check: const {});
      await h.start(tester, action: 'break_start');
      expect(find.text('Which break?'), findsNothing);
      expect(h.result, isTrue);
      expect(h.fields('/hr/attendance/break/start').containsKey('break_type_id'), isFalse);
    });

    testWidgets('ending a break that ran over asks for a reason', (tester) async {
      final h = _Harness(check: {'note_required': true, 'note_message': 'This break ran 15 min over the limit — add a reason.'});
      await h.start(tester, action: 'break_end');
      expect(find.textContaining('15 min over the limit'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('reason-field')), 'Long queue');
      await tester.tap(find.byKey(const ValueKey('punch-submit')));
      await _pump(tester);
      expect(h.fields('/hr/attendance/break/end')['note'], 'Long queue');
    });
  });

  testWidgets('clock out asks to confirm first; cancelling does nothing', (tester) async {
    final h = _Harness(check: const {});
    await h.start(tester, action: 'clock_out');
    expect(find.text('Clock out?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await _pump(tester, 10);
    expect(h.result, isFalse);
    expect(h.posts('/hr/attendance/clock-out'), isEmpty);
  });
}
