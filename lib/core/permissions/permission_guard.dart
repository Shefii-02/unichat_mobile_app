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

  /// Owner / superadmin bypass every permission check, mirroring the web app.
  static bool get isOwner =>
      _role == 'owner' || _role == 'superadmin' || _role == 'super_admin';
  static bool get isAdmin   => isOwner || _role == 'admin';
  static bool get isManager => _role == 'manager' || _role == 'team_lead' || isAdmin;
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
