import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// The one persistent bottom-nav frame. Wraps a [StatefulNavigationShell] (see
/// `StatefulShellRoute.indexedStack` in app_router.dart) — each tab keeps its own Navigator
/// and widget state alive in an [IndexedStack] behind this single Scaffold, so switching
/// tabs never rebuilds or stacks a second bottom nav on top (which a plain `ShellRoute` +
/// `context.push` to another tab's route used to do).
class MainShell extends StatelessWidget {
  const MainShell({super.key, required this.navigationShell});
  final StatefulNavigationShell navigationShell;

  static const _tabs = [
    _Tab(Icons.home_outlined, Icons.home_rounded, 'Home'),
    _Tab(Icons.people_outline_rounded, Icons.people_rounded, 'Leads'),
    _Tab(Icons.track_changes_outlined, Icons.track_changes_rounded, 'Target'),
    _Tab(Icons.fingerprint_outlined, Icons.fingerprint_rounded, 'Attend.'),
    _Tab(Icons.account_balance_wallet_outlined,
        Icons.account_balance_wallet_rounded, 'Payroll'),
    _Tab(Icons.person_outline_rounded, Icons.person_rounded, 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    final idx = navigationShell.currentIndex;

    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: idx,
        // Re-tapping the current tab resets it to its initial location (matching standard
        // bottom-nav behaviour — e.g. tapping "Leads" again while inside a lead's detail
        // page pops back to the Leads list); tapping a different tab just switches branch,
        // keeping that branch's own navigation stack exactly where it was.
        onTap: (i) => navigationShell.goBranch(i, initialLocation: i == idx),
        items: _tabs.asMap().entries.map((e) {
          final t = e.value;
          final selected = e.key == idx;
          return BottomNavigationBarItem(
            icon: Icon(selected ? t.activeIcon : t.icon),
            label: t.label,
          );
        }).toList(),
      ),
    );
  }
}

class _Tab {
  const _Tab(this.icon, this.activeIcon, this.label);
  final IconData icon;
  final IconData activeIcon;
  final String label;
}
