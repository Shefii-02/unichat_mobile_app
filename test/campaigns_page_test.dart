import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unichat_mobile_app/core/theme/app_theme.dart';
import 'package:unichat_mobile_app/features/campaigns/presentation/pages/campaigns_page.dart';

import 'support/fake_api.dart';

void main() {
  testWidgets('campaigns: schedule date shown, menu rules, edit sheet is read-only except the dates', (tester) async {
    final api = FakeApi((o) {
      if (o.method == 'GET' && o.path == '/campaigns') {
        return {
          'data': [
            {
              'id': 1, 'name': 'typist navarathrii', 'status': 'scheduled', 'created_at': '2026-10-20T10:00:00+00:00',
              'scheduled_at': '2030-10-20T15:30:00+00:00', 'starts_at': '2030-10-21T00:00:00+00:00', 'ends_at': null,
              'template': {'id': 5, 'name': 'typist_navarathrii'}, 'target_type': 'labels', 'target_labels': [1, 2],
              'throttle_per_minute': 60, 'daily_limit': 500, 'description': 'internal note', 'estimated_contacts': 738,
              'stats': {'total_contacts': 0, 'sent': 0, 'delivered': 0, 'read': 0, 'failed': 0, 'pending': 0, 'delivery_rate': 0, 'read_rate': 0},
            },
            {
              'id': 2, 'name': 'ugc navarathrii', 'status': 'running', 'created_at': '2026-10-20T10:00:00+00:00',
              'template': {'id': 6, 'name': 'ugc_net'}, 'target_type': 'all', 'throttle_per_minute': 60,
              'stats': {'total_contacts': 33, 'sent': 33, 'delivered': 30, 'read': 10, 'failed': 3, 'pending': 0, 'delivery_rate': 90.9, 'read_rate': 30.3},
            },
          ],
        };
      }
      return {'message': 'ok'};
    })..install();

    await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: const CampaignsPage()));
    await tester.pumpAndSettle();

    // list: the scheduled campaign shows its send date, the running one shows delivery rates
    expect(find.text('typist navarathrii'), findsOneWidget);
    expect(find.textContaining('Scheduled '), findsWidgets);
    expect(find.textContaining('2030'), findsWidgets);
    expect(find.textContaining('90.9%'), findsOneWidget);

    // scheduled campaign: Edit and Delete are offered, Resend is not
    await tester.tap(find.byIcon(Icons.more_vert_rounded).first);
    await tester.pumpAndSettle();
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    expect(find.text('Stats'), findsOneWidget);
    expect(find.textContaining('Resend'), findsNothing);
    await tester.tapAt(const Offset(5, 5)); // dismiss the menu
    await tester.pumpAndSettle();

    // a campaign that has started cannot be edited or deleted — only paused
    await tester.tap(find.byIcon(Icons.more_vert_rounded).last);
    await tester.pumpAndSettle();
    expect(find.text('Pause'), findsOneWidget);
    expect(find.text('Edit'), findsNothing);
    expect(find.text('Delete'), findsNothing);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    // edit sheet: fixed values in boxes, only the dates are editable
    await tester.tap(find.byIcon(Icons.more_vert_rounded).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    expect(find.text('Edit schedule'), findsOneWidget);
    expect(find.textContaining('Only the send time and the lead dates can be changed'), findsOneWidget);
    for (final box in ['CAMPAIGN NAME', 'STATUS', 'TEMPLATE', 'TARGET', 'SPEED', 'DAILY LIMIT', 'DESCRIPTION']) {
      expect(find.text(box), findsOneWidget, reason: 'read-only box $box');
    }
    expect(find.text('typist_navarathrii'), findsWidgets);
    expect(find.text('2 label(s)'), findsOneWidget);
    expect(find.text('500 per day'), findsOneWidget);
    expect(find.byType(TextField), findsNothing, reason: 'no text input — the name, speed and limit cannot be edited');
    expect(find.text('Send at'), findsOneWidget);
    expect(find.text('Lead from'), findsOneWidget);
    expect(find.text('Lead to'), findsOneWidget);

    // saving sends only the three dates
    // (no scrolling needed: Save is pinned below the scrolling part of the sheet)
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final puts = api.where('PUT', '/campaigns/1').toList();
    expect(puts, hasLength(1));
    expect((puts.single.data as Map).keys.toSet(), {'scheduled_at', 'starts_at', 'ends_at'});
    expect((puts.single.data as Map)['starts_at'], '2030-10-21');
    expect((puts.single.data as Map)['ends_at'], isNull);
  });
}
