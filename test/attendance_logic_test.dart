import 'package:flutter_test/flutter_test.dart';
import 'package:unichat_mobile_app/features/attendance/attendance_actions.dart';

void main() {
  group('who must share a location (geoRequiredFor)', () {
    test('the server decides per person', () {
      expect(geoRequiredFor({'geo_required': true, 'geofence_mandatory': true}), isTrue);
      // company switch is on, but this person works from home / is not GPS-tracked → NOT blocked
      expect(geoRequiredFor({'geo_required': false, 'geofence_mandatory': true}), isFalse);
    });

    test('an older server without geo_required keeps the old behaviour', () {
      expect(geoRequiredFor({'geofence_mandatory': true}), isTrue);
      expect(geoRequiredFor({'geofence_mandatory': false}), isFalse);
      expect(geoRequiredFor(const {}), isFalse);
    });
  });

  group('what a punch still has to ask (punchAsk)', () {
    test('on time, inside the radius → nothing: no sheet, no note box', () {
      expect(punchAsk({'radius_reason_needed': false, 'note_required': false, 'note_optional': false}), PunchAsk.nothing);
      expect(punchAsk(const {}), PunchAsk.nothing, reason: 'a precheck that could not be reached must not invent questions');
    });

    test('late reason switched OFF behaves like on time', () {
      // the server sends neither note flag when late_note_mode is off
      expect(punchAsk({'late_minutes': 80, 'late_note_mode': 'off', 'note_required': false, 'note_optional': false}), PunchAsk.nothing);
    });

    test('late reason required / optional', () {
      expect(punchAsk({'note_required': true}), PunchAsk.requiredNote);
      expect(punchAsk({'note_optional': true}), PunchAsk.optionalNote);
    });

    test('outside the office radius → alert + reason (wins over the others)', () {
      expect(punchAsk({'radius_reason_needed': true, 'note_optional': true}), PunchAsk.radiusReason);
      expect(punchAsk({'radius_reason_needed': true, 'note_required': true}), PunchAsk.radiusReason);
    });
  });

  group('break types (breakChoices)', () {
    final me = {
      'break_types': [
        {'id': 1, 'name': 'Tea', 'max_minutes': 10, 'daily_limit': 2, 'is_active': true},
        {'id': 2, 'name': 'Lunch', 'max_minutes': 45, 'daily_limit': 1, 'is_active': true},
        {'id': 3, 'name': 'Old', 'is_active': false},
        {'id': 4, 'name': 'Free', 'is_active': true},
      ],
      'today': {
        'breaks': [
          {'break_type_id': 2},
          {'break_type_id': 1},
        ],
      },
    };

    test('lists active types with how many are left today', () {
      final c = breakChoices(me);
      expect(c.map((e) => e.name), ['Tea', 'Lunch', 'Free'], reason: 'inactive types are not offered');
      expect(c[0].detail, 'up to 10 min · 1 of 2 left today');
      expect(c[0].exhausted, isFalse);
    });

    test('a type used up for the day is exhausted (greyed out in the picker)', () {
      final lunch = breakChoices(me)[1];
      expect(lunch.exhausted, isTrue);
      expect(lunch.detail, 'up to 45 min · 0 of 1 left today');
    });

    test('no limits → no detail, never exhausted; no types at all → nothing to pick', () {
      final free = breakChoices(me)[2];
      expect(free.detail, '');
      expect(free.exhausted, isFalse);
      expect(breakChoices(const {}), isEmpty);
      expect(breakChoices({'break_types': <dynamic>[]}), isEmpty);
    });
  });
}
