import 'package:flutter/material.dart';

class PermissionGuard {
  PermissionGuard._();

  static List<String> _permissions = [];
  static String _role = '';

  static void setPermissions(List<String> perms, String role) {
    _permissions = perms;
    _role = role;
  }

  static void clear() {
    _permissions = [];
    _role = '';
  }

  static bool can(String permission) =>
      isOwner || _permissions.contains(permission);
  static bool canView(String section) => can('$section.view') || isAdmin;
  static bool canManage(String section) => can('$section.manage') || isAdmin;

  // Role names come from two sources on the backend: the global system roles
  // (superadmin/owner/admin/team_lead/counsellor/viewer — lowercase) and each company's own
  // auto-seeded roles (Admin/Manager/Sales Agent/Support Agent/Viewer — Title Case). An exact
  // match against the lowercase literals alone silently misses every company's own real-world
  // "Admin" staff member (the role name a company actually assigns day to day) — normalize
  // case here so both sources are recognized identically.
  static String get _normalizedRole => _role.toLowerCase();

  /// Owner / superadmin bypass every permission check, mirroring the web app.
  static bool get isOwner =>
      _normalizedRole == 'owner' || _normalizedRole == 'superadmin' || _normalizedRole == 'super_admin';
  static bool get isAdmin   => isOwner || _normalizedRole == 'admin';
  static bool get isManager => _normalizedRole == 'manager' || _normalizedRole == 'team_lead' || isAdmin;
  static String get role    => _role;

  static List<String> get all => _permissions;
}

class PermissionWidget extends StatelessWidget {
  const PermissionWidget({
    super.key,
    required this.permission,
    required this.child,
    this.fallback,
  });

  final String permission;
  final Widget child;
  final Widget? fallback;

  @override
  Widget build(BuildContext context) {
    return PermissionGuard.can(permission)
        ? child
        : (fallback ?? const SizedBox.shrink());
  }
}
