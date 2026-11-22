import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unichat_mobile_app/core/permissions/permission_guard.dart';
import 'package:unichat_mobile_app/core/theme/app_theme.dart';
import 'package:unichat_mobile_app/features/home/team_reports.dart';

import 'support/fake_api.dart';

/// The Team block on the dashboard: company admin / team head sees EVERY member for HR, CRM and Leads.
void main() {
  tearDown(PermissionGuard.clear);

  test('who may see the team: owner, admin, team head, or HR / staff-view permission — not a plain counsellor', () {
    PermissionGuard.setPermissions(const [], 'owner');
    expect(canSeeTeam(), isTrue);
    PermissionGuard.setPermissions(const [], 'Admin');
    expect(canSeeTeam(), isTrue);
    PermissionGuard.setPermissions(const [], 'team_lead');
    expect(canSeeTeam(), isTrue, reason: 'a team head');
    PermissionGuard.setPermissions(const ['hr.attendance.view_all'], 'counsellor');
    expect(canSeeTeam(), isTrue);
    PermissionGuard.setPermissions(const ['staff.view'], 'counsellor');
    expect(canSeeTeam(), isTrue);
    PermissionGuard.setPermissions(const ['leads.view'], 'counsellor');
    expect(canSeeTeam(), isFalse);
  });

  Map<String, dynamic> payload(String section) => switch (section) {
        'hr' => {
            'section': 'hr',
            'summary': {'working': 1, 'out': 0, 'on_leave': 1, 'not_in': 1, 'late': 1, 'total': 3},
            'members': [
              {'id': 1, 'name': 'Cara', 'role': 'Counsellor', 'is_me': false, 'state': 'working', 'clock_in_at': '2026-11-22T09:40:00', 'late_minutes': 687},
              {'id': 2, 'name': 'Olive', 'role': 'Owner', 'is_me': true, 'state': 'not_in', 'late_minutes': 0},
              {'id': 3, 'name': 'Dev', 'is_me': false, 'state': 'on_leave', 'late_minutes': 0},
            ],
          },
        'crm' => {
            'section': 'crm',
            'summary': {'open_deals': 2, 'won_month': 1, 'open_tasks': 2, 'overdue_tasks': 1},
            'members': [
              {'id': 1, 'name': 'Cara', 'is_me': false, 'open_deals': 2, 'open_value': 1500, 'open_tasks': 2, 'overdue_tasks': 1},
              {'id': 2, 'name': 'Olive', 'is_me': true, 'open_deals': 0, 'open_value': 0, 'open_tasks': 0, 'overdue_tasks': 0},
            ],
          },
        _ => {
            'section': 'leads',
            'summary': {'assigned': 4, 'active': 2, 'enrolled': 1, 'new_today': 4, 'conversion': 25.0},
            'members': [
              {'id': 1, 'name': 'Cara', 'is_me': false, 'assigned': 3, 'active': 1, 'enrolled': 1, 'conversion': 33.3},
            ],
          },
      };

  Future<FakeApi> open(WidgetTester tester, {int status = 200}) async {
    final api = FakeApi((o) => status == 200 ? payload('${o.queryParameters['section']}') : FakeReply(status, {'message': 'no'}))..install();
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(theme: AppTheme.light, home: const Scaffold(body: SingleChildScrollView(child: TeamMembersPanel()))),
    ));
    for (var i = 0; i < 6; i++) { await tester.pump(const Duration(milliseconds: 60)); }
    return api;
  }

  testWidgets('HR tab: every member, their state, and lateness as H:MM (687 → 11:27 min late)', (tester) async {
    final api = await open(tester);
    expect(api.where('GET', '/analytics/team-members').single.queryParameters['section'], 'hr');
    expect(find.text('3 members'), findsOneWidget);
    expect(find.text('Cara'), findsOneWidget);
    expect(find.text('Olive (you)'), findsOneWidget);
    expect(find.text('Dev'), findsOneWidget);
    expect(find.text('11:27 min late'), findsOneWidget);
    expect(find.text('Working'), findsOneWidget); expect(find.text('On leave'), findsOneWidget); expect(find.text('Not in'), findsOneWidget);
    expect(find.text('Late 1'), findsOneWidget);
  });

  testWidgets('switching to CRM and Leads loads each section for all members', (tester) async {
    final api = await open(tester);
    await tester.tap(find.byKey(const ValueKey('team-tab-crm')));
    for (var i = 0; i < 6; i++) { await tester.pump(const Duration(milliseconds: 60)); }
    expect(find.text('2 deals · 2 tasks · 1 overdue'), findsOneWidget);
    expect(find.text('Open deals 2'), findsOneWidget);
    expect(find.text('2 members'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('team-tab-leads')));
    for (var i = 0; i < 6; i++) { await tester.pump(const Duration(milliseconds: 60)); }
    expect(find.text('3 assigned · 1 enrolled (33.3%)'), findsOneWidget);
    expect(find.text('25.0%'), findsOneWidget);
    expect(api.calls.map((c) => c.queryParameters['section']).toSet(), {'hr', 'crm', 'leads'});
  });

  testWidgets('a person the server refuses (403) sees nothing — no error text', (tester) async {
    await open(tester, status: 403);
    expect(find.textContaining('members'), findsNothing);
    expect(find.textContaining('Exception'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
