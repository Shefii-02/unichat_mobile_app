import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:unichat_mobile_app/core/permissions/permission_guard.dart';
import 'package:unichat_mobile_app/features/accounts/presentation/pages/role_sheet.dart';
import 'package:unichat_mobile_app/features/modules/module_providers.dart';
import 'package:unichat_mobile_app/features/modules/_shared.dart';

/// Roles: tap one to see its permissions by section; people who can manage roles also create and edit them.
class RolesPage extends ConsumerWidget {
  const RolesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canManage = PermissionGuard.can('roles.manage');
    Future<void> open(Map<String, dynamic>? r) async {
      if (await showRoleSheet(context, role: r)) ref.invalidate(rolesListProvider);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Roles')),
      floatingActionButton: canManage
          ? FloatingActionButton.extended(onPressed: () => open(null), icon: const Icon(Icons.add_rounded), label: const Text('New role'))
          : null,
      body: ProviderList(
        provider: rolesListProvider,
        emptyLabel: 'No roles',
        emptyIcon: Icons.badge_rounded,
        tile: (context, r) => RecordCard(
          title: str(r['label'] ?? r['name']),
          subtitle: str(r['description'] ?? '${(r['permissions'] is List ? (r['permissions'] as List).length : 0)} permissions'),
          leadingIcon: Icons.shield_rounded,
          onTap: () => open(r),
          trailing: (r['is_system'] == true) ? const StatusPill('system', color: AppPalette.cold) : null,
        ),
      ),
    );
  }
}
