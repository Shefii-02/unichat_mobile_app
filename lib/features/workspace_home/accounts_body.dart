import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:unichat_mobile_app/core/router/shell_routes.dart';
import 'package:unichat_mobile_app/core/theme/mockup_palette.dart';
import 'package:unichat_mobile_app/features/workspace_home/ws_style.dart';

/// Accounts workspace Home: net cash flow, books / receivable / payable / wallet tiles, outstanding invoices, recent entries, wallet, GST.
class AccountsBody extends ConsumerWidget {
  const AccountsBody({super.key});

  /// Sum of a number, or of every number inside a list / map (GST summaries come as per-rate breakdowns).
  static num _sum(Object? v) {
    if (v is num) return v;
    if (v is Map) return v.values.fold<num>(0, (a, e) => a + _sum(e));
    if (v is List) return v.fold<num>(0, (a, e) => a + _sum(e));
    return n(v) ?? 0;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(wsHomeProvider('accounts'));
    final home = dataOf(async);
    final acc = dataOf(ref.watch(wsAccountsProvider));
    final rcv = dataOf(ref.watch(wsReceivableProvider));
    final wallet = asMap(home?['wallet']);
    final books = asMap(home?['books']);
    final recent = asRows(home?['recent_entries']);
    final bySource = asMap(wallet?['by_source']) ?? const <String, dynamic>{};
    final invoices = asRows(rcv?['rows']).take(3).toList();
    final gst = asMap(acc?['gst']);
    final income = n(acc?['income']) ?? 0, expense = n(acc?['expense']) ?? 0, profit = n(acc?['profit']) ?? (income - expense);
    final top = income > expense ? income : expense;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (async.hasError && home == null) WsLoadError(async.error, () => ref.invalidate(wsHomeProvider('accounts'))),
      WsSummary(
        title: 'Net cash flow · this period',
        value: '${profit >= 0 ? '+' : ''}${fmtMoney(profit)}',
        badge: profit >= 0 ? 'Healthy' : 'Negative',
        progress: top > 0 ? (income / top).toDouble() : 0,
        footer: 'Money in ${fmtMoney(income)} · Money out ${fmtMoney(expense)}',
        actions: [WsHeroButton('Create invoice', () => context.goToRoute('/accounts')), WsHeroButton('Add expense', () => context.goToRoute('/accounts'), filled: false)],
      ),
      const WsAttendance(),
      WsTiles([
        ('Books', fmtNum(books?['entries_month']), 'entries · ${fmtMoney((n(acc?['cash']) ?? 0) + (n(acc?['bank']) ?? 0))} cash & bank', tintLavender, () => context.goToRoute('/accounts')),
        ('Receivable', fmtMoney(acc?['receivable']), '${fmtNum(acc?['open_invoices'])} open invoices', tintGreen, () => context.goToRoute('/accounts')),
        ('Payable', fmtMoney(acc?['payable']), '${fmtNum(acc?['open_bills'])} open bills', tintRed, () => context.goToRoute('/accounts')),
        ('Wallet', wallet == null ? '—' : fmtMoney(wallet['balance']), 'message & AI credits', tintAmber, () => context.goToRoute('/wallet')),
      ]),
      WsSection(
        title: 'Outstanding invoices',
        action: 'See all ${fmtNum(acc?['open_invoices'])}',
        onAction: () => context.goToRoute('/accounts'),
        child: WsRows([
          for (final i in invoices)
            WsRow(
              title: '${i['party'] ?? 'Customer'}',
              subtitle: '${i['number'] ?? ''} · ${(n(i['days_overdue']) ?? 0) > 0 ? 'Overdue ${i['days_overdue']} days' : 'Due ${i['due_date'] ?? ''}'}',
              trailing: Text(fmtMoney(i['outstanding']), style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
        ], empty: 'No outstanding invoices.'),
      ),
      WsSection(
        title: 'Recent entries',
        action: 'Open books',
        onAction: () => context.goToRoute('/accounts'),
        child: WsRows([
          for (final e in recent)
            WsRow(
              leading: Icon(e['direction'] == 'in' ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded, size: 20, color: e['direction'] == 'in' ? M.attMuted : M.redMuted),
              title: '${e['title'] ?? ''}',
              subtitle: '${e['date'] ?? ''}',
              trailing: Text('${e['direction'] == 'in' ? '+' : '-'}${fmtMoney(e['amount'])}', style: TextStyle(fontWeight: FontWeight.w600, color: e['direction'] == 'in' ? M.attMuted : M.redMuted)),
            ),
        ], empty: 'No entries yet.'),
      ),
      WsSection(
        title: 'Wallet',
        action: 'Top up',
        onAction: () => context.goToRoute('/wallet'),
        child: WsRows([
          WsRow(title: 'Available balance', trailing: Text(wallet == null ? '—' : fmtMoney(wallet['balance']), style: const TextStyle(fontWeight: FontWeight.w700))),
          WsRow(title: 'Spent this month', trailing: Text(fmtMoney(wallet?['spent_month']), style: const TextStyle(fontWeight: FontWeight.w600))),
          for (final e in bySource.entries) WsRow(title: e.key.replaceAll('_', ' '), trailing: Text('${fmtNum(e.value)} credits', style: const TextStyle(fontWeight: FontWeight.w600))),
        ]),
      ),
      WsSection(
        title: 'GST',
        child: WsRows([
          WsRow(title: 'Output GST', trailing: Text(fmtMoney(_sum(gst?['outward'])), style: const TextStyle(fontWeight: FontWeight.w600))),
          WsRow(title: 'Input credit', trailing: Text(fmtMoney(_sum(gst?['itc'])), style: const TextStyle(fontWeight: FontWeight.w600))),
          WsRow(title: 'Payable', trailing: Text(fmtMoney(gst?['total_payable']), style: const TextStyle(fontWeight: FontWeight.w700, color: M.amberMuted))),
        ]),
      ),
      const SizedBox(height: 12),
    ]);
  }
}
