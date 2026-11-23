import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:unichat_mobile_app/core/storage/local_storage.dart';
import 'package:unichat_mobile_app/features/auth/data/models/user_model.dart';
import 'package:unichat_mobile_app/features/auth/presentation/providers/auth_provider.dart';

/// One "workspace" a user can view Home as — one of their access sections (Staff Access → main + sub sections).
class Workspace {
  const Workspace(this.key, this.title, this.icon);
  final String key;
  final String title;
  final IconData icon;
}

/// Section key → workspace.
const _byKey = <String, Workspace>{
  'company_admin': Workspace('company_admin', 'Company Admin', Icons.admin_panel_settings_outlined),
  'administrators': Workspace('administrators', 'Administrators', Icons.shield_outlined),
  'sales': Workspace('sales', 'Sales Team', Icons.trending_up_rounded),
  'marketing': Workspace('marketing', 'Marketing Team', Icons.campaign_outlined),
  'hr': Workspace('hr', 'HR Team', Icons.groups_outlined),
  'accounts': Workspace('accounts', 'Accounts Team', Icons.account_balance_wallet_outlined),
};

/// The workspaces [u] may switch between: only their own access sections, main first, each once. Unknown keys are skipped.
List<Workspace> workspacesFor(UserModel? u) {
  final out = <Workspace>[];
  for (final s in u?.accessSections ?? const <String>[]) {
    final w = _byKey[s];
    if (w != null && !out.any((e) => e.key == w.key)) out.add(w);
  }
  return out;
}

Workspace? workspaceByKey(String? key) => key == null ? null : _byKey[key];

const _kWorkspace = 'home_workspace';

/// The workspace Home is showing. Defaults to the user's main section; the dropdown in the Home header changes it (and it is remembered).
class ActiveWorkspace extends Notifier<String?> {
  @override
  String? build() {
    final user = ref.watch(authProvider).value;
    final mine = workspacesFor(user);
    if (mine.isEmpty) return null;
    final saved = LocalStorage.getString(_kWorkspace);
    if (mine.any((w) => w.key == saved)) return saved;
    // Opens on Company Admin when the user has it (the dashboard they already know), otherwise on their main section.
    return mine.any((w) => w.key == 'company_admin') ? 'company_admin' : mine.first.key;
  }

  Future<void> choose(String key) async {
    state = key;
    await LocalStorage.setString(_kWorkspace, key);
  }
}

final activeWorkspaceProvider = NotifierProvider<ActiveWorkspace, String?>(ActiveWorkspace.new);
