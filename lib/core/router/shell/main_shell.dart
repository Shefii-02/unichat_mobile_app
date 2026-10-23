import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:unichat_mobile_app/core/constants/app_colors.dart';

/// The one persistent bottom-nav frame. Wraps a [StatefulNavigationShell] (see
/// `StatefulShellRoute.indexedStack` in app_router.dart) — each tab keeps its own Navigator
/// and widget state alive in an [IndexedStack] behind this single Scaffold, so switching
/// tabs never rebuilds or stacks a second bottom nav on top (which a plain `ShellRoute` +
/// `context.push` to another tab's route used to do).
///
/// Seven slots; the centre "Explore" button is raised above the bar. [_Tab.branch] is the
/// index of the shell branch in app_router.dart (Leads/Target branches have no slot).
class MainShell extends StatelessWidget {
  const MainShell({super.key, required this.navigationShell});
  final StatefulNavigationShell navigationShell;

  static const _tabs = [
    _Tab(0, Icons.home_outlined, Icons.home_rounded, 'Home'),
    _Tab(1, Icons.checklist_rounded, Icons.checklist_rounded, 'Todo'),
    _Tab(2, Icons.chat_bubble_outline_rounded, Icons.chat_bubble_rounded, 'Chats'),
    _Tab(3, Icons.explore_outlined, Icons.explore_rounded, 'Explore', raised: true),
    _Tab(4, Icons.fingerprint_outlined, Icons.fingerprint_rounded, 'Attendance'),
    _Tab(5, Icons.account_balance_wallet_outlined, Icons.account_balance_wallet_rounded, 'Payroll'),
    _Tab(6, Icons.person_outline_rounded, Icons.person_rounded, 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    final idx = navigationShell.currentIndex;
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).padding.bottom;
    const barH = 64.0, lift = 22.0;

    return Scaffold(
      body: navigationShell,
      // The raised button pokes above the bar, and a Stack can't be tapped outside its own bounds — so the
      // frame is [lift] taller than the bar itself, with the bar drawn in its lower part.
      bottomNavigationBar: SizedBox(
        height: barH + lift + bottomInset,
        child: Stack(children: [
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: barH + bottomInset,
            child: Material(
              color: theme.colorScheme.surface,
              elevation: 12,
              child: Padding(
                padding: EdgeInsets.only(bottom: bottomInset),
                child: Row(children: [
                  for (final t in _tabs)
                    Expanded(
                      child: t.raised
                          ? const SizedBox.shrink()
                          : InkResponse(
                              // Re-tapping the current tab resets it to its initial location; a different tab
                              // just switches branch, keeping that branch's own navigation stack where it was.
                              onTap: () => navigationShell.goBranch(t.branch, initialLocation: t.branch == idx),
                              child: _item(theme, t, t.branch == idx),
                            ),
                    ),
                ]),
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Center(child: _raised(theme, _tabs[3], idx == 3, () => navigationShell.goBranch(3, initialLocation: idx == 3))),
          ),
        ]),
      ),
    );
  }

  Widget _item(ThemeData theme, _Tab t, bool selected) {
    final color = selected ? AppColors.primary : theme.colorScheme.onSurface.withValues(alpha: 0.55);
    return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(selected ? t.activeIcon : t.icon, size: 24, color: color),
      const SizedBox(height: 2),
      Text(t.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10, fontWeight: selected ? FontWeight.w700 : FontWeight.w500, color: color)),
    ]);
  }

  Widget _raised(ThemeData theme, _Tab t, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.primary,
            border: Border.all(color: theme.colorScheme.surface, width: 4),
            boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 10, offset: Offset(0, 4))],
          ),
          child: Icon(selected ? t.activeIcon : t.icon, color: Colors.white, size: 28),
        ),
        const SizedBox(height: 2),
        Text(t.label, style: TextStyle(fontSize: 10, fontWeight: selected ? FontWeight.w700 : FontWeight.w500, color: selected ? AppColors.primary : theme.colorScheme.onSurface.withValues(alpha: 0.55))),
      ]),
    );
  }
}

class _Tab {
  const _Tab(this.branch, this.icon, this.activeIcon, this.label, {this.raised = false});
  final int branch;
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool raised;
}
