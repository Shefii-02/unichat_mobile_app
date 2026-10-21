import 'package:flutter/material.dart';
import 'books_dashboard_tab.dart';
import 'books_gst_tab.dart';
import 'books_items_tab.dart';
import 'books_ledgers_tab.dart';
import 'books_reports_tab.dart';
import 'books_settings_tab.dart';
import 'books_vouchers_tab.dart';

/// Accounts — double-entry books, vouchers, GST and reports (mirrors the web `/accounts` section).
class BooksPage extends StatelessWidget {
  const BooksPage({super.key});

  @override
  Widget build(BuildContext context) {
    const tabs = ['Dashboard', 'Vouchers', 'Ledgers', 'Items', 'Reports', 'GST', 'Settings'];
    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Accounts'),
          bottom: TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: [for (final t in tabs) Tab(text: t)]),
        ),
        body: const TabBarView(children: [
          BooksDashboardTab(),
          BooksVouchersTab(),
          BooksLedgersTab(),
          BooksItemsTab(),
          BooksReportsTab(),
          BooksGstTab(),
          BooksSettingsTab(),
        ]),
      ),
    );
  }
}
