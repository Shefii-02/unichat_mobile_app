import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class MainShell extends StatelessWidget {
  const MainShell({super.key, required this.child});
  final Widget child;

  static const _tabs = [
    _Tab('/home', Icons.home_outlined, Icons.home_rounded, 'Home'),
    _Tab('/leads', Icons.people_outline_rounded, Icons.people_rounded, 'Leads'),
    _Tab('/target', Icons.track_changes_outlined, Icons.track_changes_rounded,
        'Target'),
    _Tab('/attendance', Icons.fingerprint_outlined, Icons.fingerprint_rounded,
        'Attend.'),
    _Tab('/payroll', Icons.account_balance_wallet_outlined,
        Icons.account_balance_wallet_rounded, 'Payroll'),
    _Tab('/profile', Icons.person_outline_rounded, Icons.person_rounded,
        'Profile'),
  ];

  int _tabIndex(String location) {
    for (int i = 0; i < _tabs.length; i++) {
      if (location.startsWith(_tabs[i].route)) return i;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    final idx = _tabIndex(location);

    return Scaffold(
      body: child,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: idx,
        onTap: (i) => context.go(_tabs[i].route),
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
  const _Tab(this.route, this.icon, this.activeIcon, this.label);
  final String route;
  final IconData icon;
  final IconData activeIcon;
  final String label;
}
