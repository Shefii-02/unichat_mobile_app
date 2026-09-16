import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:unichat_mobile_app/core/storage/local_storage.dart';
import 'package:unichat_mobile_app/features/app_lock/app_lock_provider.dart';

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
      body: Stack(
        children: [
          navigationShell,
          const _AppLockHintNudge(),
        ],
      ),
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

/// Renders nothing — its only job is to show a one-time, dismissible heads-up (never a
/// blocking dialog) that app lock / biometric login exist and can be turned on in Settings.
/// Fires at most once ever per device install (tracked via [LocalStorage.kAppLockHintSeen]),
/// and only when the user hasn't already set one up. This is the entire "first run" touch
/// point for app lock — actual setup only ever happens if the user goes and opts in.
class _AppLockHintNudge extends ConsumerStatefulWidget {
  const _AppLockHintNudge();
  @override
  ConsumerState<_AppLockHintNudge> createState() => _AppLockHintNudgeState();
}

class _AppLockHintNudgeState extends ConsumerState<_AppLockHintNudge> {
  bool _checked = false;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appLockProvider);
    if (!_checked && state.loaded) {
      _checked = true;
      final alreadySeen = LocalStorage.getBool(LocalStorage.kAppLockHintSeen);
      if (!alreadySeen && !state.hasMpin) {
        LocalStorage.setBool(LocalStorage.kAppLockHintSeen, true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              duration: const Duration(seconds: 6),
              content: const Text('Tip: you can set up an app lock PIN and biometric login anytime in Settings.'),
              action: SnackBarAction(
                label: 'Settings',
                onPressed: () => context.push('/settings'),
              ),
            ),
          );
        });
      }
    }
    return const SizedBox.shrink();
  }
}
