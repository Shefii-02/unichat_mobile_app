import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Root paths of the bottom-nav [StatefulShellRoute] branches (see app_router.dart). Any
/// generic "navigate to this route" call (module tiles, quick actions, search results) must
/// route these through [goToRoute] rather than a raw `context.push`, which would stack a
/// second shell — and a second bottom nav — on top of the current one instead of switching
/// tabs.
const shellBranchRoutes = {'/home', '/leads', '/target', '/attendance', '/payroll', '/profile'};

extension ShellAwareNavigation on BuildContext {
  /// Switches tabs (via `go`) if [route] is a bottom-nav branch root, otherwise pushes it as
  /// a normal screen on top of the current one.
  void goToRoute(String route) {
    if (shellBranchRoutes.contains(route)) {
      go(route);
    } else {
      push(route);
    }
  }
}
