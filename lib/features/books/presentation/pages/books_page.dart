import 'package:flutter/material.dart';
import 'package:unichat_mobile_app/core/permissions/permission_guard.dart';
import 'books_dashboard_tab.dart';
import 'books_gst_tab.dart';
import 'books_items_tab.dart';
import 'books_ledgers_tab.dart';
import 'books_reports_tab.dart';
import 'books_settings_tab.dart';
import 'books_vouchers_tab.dart';

/// Accounts — double-entry books, vouchers, GST and reports (mirrors the web `/accounts` section).
///
/// Different accounts roles see different screens: anyone with `accounts.read` gets the everyday books (dashboard, vouchers, ledgers,
/// items, reports); GST and Settings change how the books work, so they need `accounts.manage` (owners and admins always have it).
class BooksPage extends StatelessWidget {
  const BooksPage({super.key});

  @override
  Widget build(BuildContext context) {
    final manage = PermissionGuard.canManage('accounts');
    final screens = <(String, Widget)>[
      ('Dashboard', const BooksDashboardTab()),
      ('Vouchers', const BooksVouchersTab()),
      ('Ledgers', const BooksLedgersTab()),
      ('Items', const BooksItemsTab()),
      ('Reports', const BooksReportsTab()),
      if (manage) ('GST', const BooksGstTab()),
      if (manage) ('Settings', const BooksSettingsTab()),
    ];
    return DefaultTabController(
      length: screens.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Accounts'),
          bottom: TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: [for (final t in screens) Tab(text: t.$1)]),
        ),
        body: TabBarView(children: [for (final t in screens) t.$2]),
      ),
    );
  }
}
