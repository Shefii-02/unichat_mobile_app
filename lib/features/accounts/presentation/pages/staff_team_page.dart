// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:unichat_mobile_app/core/permissions/permission_guard.dart';
import 'package:unichat_mobile_app/features/accounts/presentation/pages/staff_access_sheet.dart';
import 'package:unichat_mobile_app/features/modules/module_providers.dart';
import 'package:unichat_mobile_app/features/modules/_shared.dart';

/// Split out of the former shared `StaffPage` (tab 0, "Team") — an independent page instead
/// of one class shared with `RolesPage` via a tab index.
class StaffTeamPage extends ConsumerWidget {
  const StaffTeamPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Staff')),
      // "Add staff" and every per-row action below previously rendered unconditionally —
      // reachable by anyone who could open this page at all (staff.view), not just staff.manage.
      floatingActionButton: PermissionGuard.can('staff.manage')
          ? FloatingActionButton.extended(
              onPressed: () => _edit(context, ref, null),
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: const Text('Add staff'),
            )
          : null,
      body: ProviderList(
        provider: staffListProvider,
        emptyLabel: 'No staff members',
        emptyIcon: Icons.groups_rounded,
        tile: (context, s) {
          final role = s['role'] is Map
              ? str((s['role'] as Map)['label'] ?? (s['role'] as Map)['name'])
              : str(s['role'] ?? s['role_name']);
          final active = s['is_active'] == true || s['active'] == true;
          return RecordCard(
            title: str(s['name']),
            subtitle: '${str(s['email'])} · $role',
            leadingIcon: Icons.person_rounded,
            onTap: () => _edit(context, ref, s),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                StatusPill(active ? 'active' : 'inactive'),
                RowMenu(items: PermissionGuard.can('staff.manage') ? [
                  ('Edit', Icons.edit_rounded, () => _edit(context, ref, s)),
                  ('Access (portal / mobile / sections)', Icons.admin_panel_settings_rounded, () => showStaffAccessSheet(context, s)),
                  (
                    active ? 'Deactivate' : 'Activate',
                    Icons.toggle_on_rounded,
                    () async {
                      final ok = await runAction(
                          context,
                          () => Api.patch('/staff/${s['id']}/toggle-active'),
                          success: 'Updated');
                      if (ok) ref.invalidate(staffListProvider);
                    }
                  ),
                  (
                    'Reset password',
                    Icons.lock_reset_rounded,
                    () => _resetPassword(context, s),
                  ),
                  (
                    'Delete',
                    Icons.delete_rounded,
                    () async {
                      if (!await confirm(context,
                          title: 'Remove staff member?',
                          message:
                              'Their leads will be unassigned. This cannot be undone.',
                          destructive: true,
                          confirmLabel: 'Remove')) { return; }
                      final ok = await runAction(context,
                          () => Api.delete('/staff/${s['id']}'),
                          success: 'Removed');
                      if (ok) ref.invalidate(staffListProvider);
                    }
                  ),
                ] : const []),
              ],
            ),
            footer: s['department'] != null
                ? Align(
                    alignment: Alignment.centerLeft,
                    child: StatusPill(str(s['department']),
                        color: AppPalette.info))
                : null,
          );
        },
      ),
    );
  }

  Future<List<Rec>> _safeList(String path) async {
    try {
      return await Api.list(path);
    } catch (_) {
      return const [];
    }
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, Rec? s) async {
    final roles = await _safeList('/roles');
    if (!context.mounted) return;
    final data = <String, dynamic>{};
    final creating = s == null;
    Rec? initialRole;
    if (s != null && s['role'] is Map) {
      initialRole = roles.firstWhere(
        (r) => r['id'] == (s['role'] as Map)['id'],
        orElse: () => <String, dynamic>{},
      );
      if (initialRole.isEmpty) initialRole = null;
    }
    final ok = await showFormSheet(
      context,
      title: creating ? 'Add staff member' : 'Edit ${str(s['name'])}',
      fields: (ctx) => [
        FText(
          label: 'Name',
          required: creating,
          initial: s?['name'] as String?,
          onSaved: (v) => v.isEmpty ? null : data['name'] = v,
        ),
        if (creating) ...[
          FText(
            label: 'Email',
            required: true,
            keyboardType: TextInputType.emailAddress,
            onSaved: (v) => data['email'] = v,
          ),
          FText(
            label: 'Password',
            required: true,
            obscure: true,
            hint: 'Min 8 characters',
            onSaved: (v) {
              data['password'] = v;
              data['password_confirmation'] = v;
            },
          ),
        ],
        if (roles.isNotEmpty)
          FSelect<Rec>(
            label: 'Role',
            options: roles,
            initial: initialRole,
            labelOf: (r) => str(r['label'] ?? r['name']),
            onSaved: (r) => r?['id'] != null ? data['role_id'] = r!['id'] : null,
          ),
        FText(
          label: 'Phone',
          keyboardType: TextInputType.phone,
          initial: s?['phone'] as String?,
          onSaved: (v) => v.isEmpty ? null : data['phone'] = v,
        ),
        FText(
          label: 'Department',
          initial: s?['department'] as String?,
          onSaved: (v) => v.isEmpty ? null : data['department'] = v,
        ),
        FNumber(
          label: 'Max leads',
          initial: num.tryParse('${s?['max_leads'] ?? ''}'),
          onSaved: (v) => v == null ? null : data['max_leads'] = v.toInt(),
        ),
      ],
      onSubmit: () => creating
          ? Api.post('/staff', data: data)
          : Api.put('/staff/${s['id']}', data: data),
    );
    if (ok) ref.invalidate(staffListProvider);
  }

  Future<void> _resetPassword(BuildContext context, Rec s) async {
    final data = <String, dynamic>{};
    await showFormSheet(
      context,
      title: 'Reset password — ${str(s['name'])}',
      submitLabel: 'Reset',
      fields: (ctx) => [
        FText(
          label: 'New password',
          required: true,
          obscure: true,
          hint: 'Min 8 characters',
          onSaved: (v) {
            data['password'] = v;
            data['password_confirmation'] = v;
          },
        ),
      ],
      onSubmit: () => Api.patch('/staff/${s['id']}/reset-password', data: data),
    );
  }
}
