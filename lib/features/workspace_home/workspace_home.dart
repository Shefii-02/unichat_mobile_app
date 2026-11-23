import 'package:flutter/widgets.dart';
import 'package:unichat_mobile_app/features/workspace_home/accounts_body.dart';
import 'package:unichat_mobile_app/features/workspace_home/admin_body.dart';
import 'package:unichat_mobile_app/features/workspace_home/hr_body.dart';
import 'package:unichat_mobile_app/features/workspace_home/marketing_body.dart';
import 'package:unichat_mobile_app/features/workspace_home/sales_body.dart';

export 'package:unichat_mobile_app/features/workspace_home/ws_style.dart' show wsHomeProvider, wsAccountsProvider, wsReceivableProvider;

/// The body (everything under the Home header) of a workspace, or null for Company Admin — that keeps the original Home content.
Widget? workspaceBodyFor(String? key) => switch (key) {
      'sales' => const SalesBody(),
      'administrators' => const AdminBody(),
      'hr' => const HrBody(),
      'marketing' => const MarketingBody(),
      'accounts' => const AccountsBody(),
      _ => null,
    };
