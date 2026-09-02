import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:badges/badges.dart' as bdg;
import 'package:unichat_mobile_app/core/constants/app_colors.dart';

class MainShell extends StatelessWidget {
  const MainShell({super.key, required this.child});
  final Widget child;

  static const _tabs = [
    _Tab('/chats',     Icons.chat_bubble_outline_rounded,  Icons.chat_bubble_rounded,  'Chats'),
    _Tab('/leads',     Icons.people_outline_rounded,        Icons.people_rounded,        'Leads'),
    _Tab('/dashboard', Icons.grid_view_rounded,             Icons.grid_view_rounded,     'Dashboard'),
    _Tab('/contacts',  Icons.contacts_outlined,             Icons.contacts_rounded,      'Contacts'),
    _Tab('/more',      Icons.more_horiz_rounded,            Icons.more_horiz_rounded,    'More'),
  ];

  int _tabIndex(String location) {
    for (int i = 0; i < _tabs.length; i++) {
      if (location.startsWith(_tabs[i].route)) return i;
    }
    return 2;
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
