import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unichat_mobile_app/core/nav/app_modules.dart';
import 'package:unichat_mobile_app/core/theme/app_theme.dart';
import 'package:unichat_mobile_app/features/section_dashboards/section_dashboard_page.dart';

import 'support/fake_api.dart';

/// Tasks / Meta Ads / Instagram / Messenger / AI Agent each get their own dashboard in the app, all from one server payload shape.
void main() {
  List<Map<String, dynamic>> pts() => [
        for (var i = 0; i < 30; i++) {'date': '2026-11-${(i + 1).toString().padLeft(2, '0')}', 'value': i % 5},
      ];
  Map<String, dynamic> payload() => {
        'title': 'Meta Ads · last 30 days',
        'range_days': 30,
        'kpis': [
          {'label': 'Spend (30 d)', 'value': 1234567.5, 'format': 'money'},
          {'label': 'CTR', 'value': 1.14, 'format': 'percent'},
          {'label': 'Overdue', 'value': 2, 'tone': 'red'},
          {'label': 'Impressions', 'value': 71000},
        ],
        'series': {
          'title': 'Daily spend and leads',
          'lines': [
            {'label': 'Spend', 'color': '#6366f1', 'points': pts()},
            {'label': 'Leads', 'color': '#16a34a', 'points': pts()},
          ],
        },
        'lists': [
          {'title': 'Top campaigns by spend', 'columns': ['Campaign', 'Spend'], 'rows': [['Diwali', 1500], ['Old', 200]]},
          {'title': 'Empty one', 'columns': ['A'], 'rows': []},
        ],
      };

  Future<FakeApi> open(WidgetTester tester, {String title = 'Meta Ads', String endpoint = '/meta-ads/dashboard', String channel = '', }) async {
    tester.view.physicalSize = const Size(900, 3200);   // tall enough to build every card of the lazy list
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = FakeApi((o) => payload())..install();
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(theme: AppTheme.light, home: SectionDashboardPage(title: title, endpoint: endpoint, channel: channel)),
    ));
    for (var i = 0; i < 8; i++) { await tester.pump(const Duration(milliseconds: 100)); }   // a failing request may wait out the app's retry delay first
    return api;
  }

  test('numbers use Indian grouping, money and percent formats', () {
    expect(groupIndian('7'), '7'); expect(groupIndian('1234'), '1,234'); expect(groupIndian('123456'), '1,23,456'); expect(groupIndian('12345678'), '1,23,45,678');
    expect(formatKpi({'value': 1234567.5, 'format': 'money'}), '₹12,34,567.50');
    expect(formatKpi({'value': 1700, 'format': 'money'}), '₹1,700');
    expect(formatKpi({'value': 1.14, 'format': 'percent'}), '1.14%');
    expect(formatKpi({'value': 71000}), '71,000');
  });

  testWidgets('shows the headline numbers, the chart and the lists, and asks the right endpoint', (tester) async {
    final api = await open(tester);
    expect(find.text('Meta Ads Dashboard'), findsOneWidget);
    expect(find.byWidgetPredicate((w) => w.key is ValueKey && '${(w.key as ValueKey).value}'.startsWith('kpi-')), findsNWidgets(4));
    expect(find.byWidgetPredicate((w) => w.key is ValueKey && '${(w.key as ValueKey).value}'.startsWith('dash-list-')), findsNWidgets(2));
    expect(find.text('₹12,34,567.50'), findsOneWidget);
    expect(find.text('1.14%'), findsOneWidget);
    expect(find.text('71,000'), findsOneWidget);
    expect(find.byKey(const ValueKey('dash-chart')), findsOneWidget);
    expect(find.text('Daily spend and leads · last 30 days'), findsOneWidget);
    expect(find.text('Diwali'), findsOneWidget);
    expect(find.text('Nothing here yet.'), findsOneWidget);
    final call = api.where('GET', '/meta-ads/dashboard').single;
    expect(call.queryParameters.containsKey('channel'), isFalse);
  });

  testWidgets('Messenger is the Instagram endpoint with channel=facebook', (tester) async {
    final api = await open(tester, title: 'Messenger', endpoint: '/instagram/dashboard', channel: 'facebook');
    expect(find.text('Messenger Dashboard'), findsOneWidget);
    expect(api.where('GET', '/instagram/dashboard').single.queryParameters['channel'], 'facebook');
  });

  testWidgets('a failure shows a friendly message, not a broken page', (tester) async {
    // the provider itself fails (the real network layer touches secure storage on errors, which a unit test cannot answer)
    await tester.pumpWidget(ProviderScope(
      overrides: [sectionDashProvider.overrideWith((ref, k) => Future<Map<String, dynamic>>.error('boom'))],
      child: MaterialApp(theme: AppTheme.light, home: const SectionDashboardPage(title: 'Tasks', endpoint: '/tasks/dashboard')),
    ));
    for (var i = 0; i < 5; i++) { await tester.pump(const Duration(milliseconds: 50)); }
    expect(find.byKey(const ValueKey('dash-error')), findsOneWidget);
    expect(find.textContaining('Could not load the dashboard'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('each of the five sections has its own Dashboard tile, first in its group, on the right module', () {
    final all = AppModules.all;
    AppModule m(String id) => all.firstWhere((x) => x.id == id);
    expect(m('tasks_dashboard').route, '/tasks/dashboard');
    expect(m('meta_dashboard').route, '/meta-ads/dashboard');
    expect(m('instagram_dashboard').route, '/instagram/dashboard');
    expect(m('messenger_dashboard').route, '/messenger/dashboard');
    expect(m('ai_dashboard').route, '/ai-agent/dashboard');
    expect(m('tasks_dashboard').entitlementModule, 'tasks');
    expect(m('messenger_dashboard').entitlementModule, 'social_dm');
    expect(m('instagram_dashboard').entitlementModule, 'social_dm');
    expect(m('meta_dashboard').entitlementModule, 'meta_ads');
    expect(m('ai_dashboard').entitlementModule, 'ai_agent');
    expect(all.where((x) => x.group == ModuleGroup.waAgents).first.id, 'ai_dashboard');
    expect(all.where((x) => x.group == ModuleGroup.metaInstagram).first.id, 'meta_dashboard');
  });
}
