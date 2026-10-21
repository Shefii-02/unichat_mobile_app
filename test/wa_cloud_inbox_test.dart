import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unichat_mobile_app/core/theme/app_theme.dart';
import 'package:unichat_mobile_app/features/modules/_shared.dart' show RecordCard;
import 'package:unichat_mobile_app/features/wa_cloud/presentation/pages/wa_cloud_inbox_page.dart';

import 'support/fake_api.dart';

Map<String, dynamic> _conv(int i) => {
      'id': i, 'contact_name': 'Customer $i', 'phone': '9190000${i.toString().padLeft(5, '0')}', 'unread_count': i % 4 == 0 ? 2 : 0,
      'assigned_to': null, 'last_message_at': '2026-10-21T09:00:00+00:00', 'last_message': {'content': {'body': 'hello $i'}, 'type': 'text'},
    };

void main() {
  testWidgets('inbox: tabs, pages of 30 load as you scroll, search is sent to the server', (tester) async {
    final api = FakeApi((o) {
      if (o.method == 'GET' && o.path == '/conversations') {
        final page = int.tryParse('${o.queryParameters['page']}') ?? 1;
        final search = '${o.queryParameters['search'] ?? ''}';
        if (search.isNotEmpty) return {'conversations': [_conv(44)], 'total': 1, 'page': 1, 'has_more': false};
        return page == 1
            ? {'conversations': [for (var i = 1; i <= 30; i++) _conv(i)], 'total': 45, 'page': 1, 'has_more': true}
            : {'conversations': [for (var i = 31; i <= 45; i++) _conv(i)], 'total': 45, 'page': 2, 'has_more': false};
      }
      return {};
    })..install();

    await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: const WaCloudInboxPage()));
    await tester.pumpAndSettle();

    // the four tabs
    for (final t in ['Unread', 'All', 'Mine', 'Unassigned']) {
      expect(find.widgetWithText(ChoiceChip, t), findsOneWidget, reason: 'tab $t');
    }
    expect(find.text('Customer 1'), findsOneWidget);
    expect(api.where('GET', '/conversations').map((c) => c.queryParameters['page']), [1]);

    // scrolling to the end pulls in page 2 by itself, and the footer then says everything is loaded
    final listScrollable = find.descendant(of: find.byType(RefreshIndicator), matching: find.byType(Scrollable)).first;
    await tester.fling(listScrollable, const Offset(0, -20000), 8000);
    await tester.pumpAndSettle();
    await tester.fling(listScrollable, const Offset(0, -20000), 8000);
    await tester.pumpAndSettle();
    final pages = api.where('GET', '/conversations').map((c) => c.queryParameters['page']).toList();
    expect(pages, containsAllInOrder([1, 2]), reason: 'the next page is requested when the end is reached');
    expect(find.textContaining('45 conversations · all loaded'), findsOneWidget);
    expect(find.text('Customer 45'), findsOneWidget);

    // switching tab asks the server for that filter (page 1 again)
    await tester.tap(find.widgetWithText(ChoiceChip, 'Unread'));
    await tester.pumpAndSettle();
    expect(api.calls.last.queryParameters['unread'], 1);
    expect(api.calls.last.queryParameters['page'], 1);

    // search goes to the server, so a chat that is not loaded can be found
    await tester.enterText(find.byType(TextField).first, 'Customer 44');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(api.calls.last.queryParameters['search'], 'Customer 44');
    expect(find.byType(RecordCard), findsOneWidget, reason: 'only the matching chat is listed');
    expect(find.descendant(of: find.byType(RecordCard), matching: find.text('Customer 44')), findsOneWidget);
  });

  testWidgets('inbox thread: opens on the newest messages and loads earlier ones with before_id', (tester) async {
    Map<String, dynamic> msg(int i) => {'id': i, 'direction': i.isOdd ? 'inbound' : 'outbound', 'type': 'text', 'status': 'delivered', 'content': {'body': 'msg $i'}, 'created_at': '2026-10-21T09:00:00+00:00'};
    final api = FakeApi((o) {
      if (o.method == 'GET' && o.path == '/conversations') {
        return {'conversations': [_conv(1)], 'total': 1, 'page': 1, 'has_more': false};
      }
      if (o.method == 'GET' && o.path == '/conversations/1/messages') {
        final before = o.queryParameters['before_id'];
        return before == null
            ? {'conversation': _conv(1), 'messages': [for (var i = 51; i <= 100; i++) msg(i)], 'has_more': true}
            : {'conversation': _conv(1), 'messages': [for (var i = 1; i <= 50; i++) msg(i)], 'has_more': false};
      }
      return {};
    })..install();

    await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: const WaCloudInboxPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Customer 1'));
    await tester.pumpAndSettle();

    // newest message is on screen; earlier ones are not loaded yet
    expect(find.text('msg 100'), findsOneWidget);
    expect(find.text('msg 1'), findsNothing);
    expect(api.where('GET', '/conversations/1/messages').single.queryParameters.containsKey('before_id'), isFalse);

    // scroll to the top: the older page is requested with the id of the oldest message we hold
    final thread = find.byType(Scrollable).first;
    await tester.fling(thread, const Offset(0, 30000), 10000);
    await tester.pumpAndSettle();
    final older = api.where('GET', '/conversations/1/messages').where((c) => c.queryParameters.containsKey('before_id')).toList();
    expect(older, isNotEmpty, reason: 'scrolling to the top loads earlier messages');
    expect(older.first.queryParameters['before_id'], 51);

    // and the very beginning is marked
    await tester.fling(thread, const Offset(0, 30000), 10000);
    await tester.pumpAndSettle();
    expect(find.text('Start of conversation'), findsOneWidget);
  });
}
