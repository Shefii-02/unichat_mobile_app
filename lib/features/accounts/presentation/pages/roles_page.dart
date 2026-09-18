import 'package:flutter/material.dart';
import 'package:unichat_mobile_app/features/modules/module_providers.dart';
import 'package:unichat_mobile_app/features/modules/_shared.dart';

/// Split out of the former shared `StaffPage` (tab 1, "Roles") — an independent page instead
/// of one class shared with `StaffTeamPage` via a tab index.
class RolesPage extends StatelessWidget {
  const RolesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Roles')),
      body: ProviderList(
        provider: rolesListProvider,
        emptyLabel: 'No roles',
        emptyIcon: Icons.badge_rounded,
        tile: (context, r) => RecordCard(
          title: str(r['label'] ?? r['name']),
          subtitle: str(r['description'] ??
              '${(r['permissions'] is List ? (r['permissions'] as List).length : 0)} permissions'),
          leadingIcon: Icons.shield_rounded,
          trailing: (r['is_system'] == true)
              ? const StatusPill('system', color: AppPalette.cold)
              : null,
        ),
      ),
    );
  }
}
