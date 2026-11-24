import 'package:flutter/material.dart';
import 'package:unichat_mobile_app/features/workspace/workspace_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:unichat_mobile_app/core/constants/app_colors.dart';
import 'package:unichat_mobile_app/core/nav/hidden_modules_provider.dart';
import 'package:unichat_mobile_app/core/version/update_checker.dart';
import 'package:unichat_mobile_app/features/quick_access/quick_access_sheet.dart';
import 'package:unichat_mobile_app/core/nav/mobile_config_provider.dart';
import 'package:unichat_mobile_app/core/permissions/permission_guard.dart';
import 'package:unichat_mobile_app/features/team_chat/team_chat_data.dart';
import 'package:unichat_mobile_app/services/push_service.dart';
import 'package:unichat_mobile_app/features/leads/presentation/widgets/lead_offer_dialog.dart';

/// The one persistent bottom-nav frame. Wraps a [StatefulNavigationShell] (see
/// `StatefulShellRoute.indexedStack` in app_router.dart) — each tab keeps its own Navigator
/// and widget state alive in an [IndexedStack] behind this single Scaffold, so switching
/// tabs never rebuilds or stacks a second bottom nav on top (which a plain `ShellRoute` +
/// `context.push` to another tab's route used to do).
///
/// Seven slots; the centre "Explore" button is raised above the bar. [_Tab.branch] is the
/// index of the shell branch in app_router.dart (Leads/Target branches have no slot).
class MainShell extends ConsumerWidget {
  const MainShell({super.key, required this.navigationShell});
  final StatefulNavigationShell navigationShell;

  static const _tabs = [
    _Tab(0, Icons.home_outlined, Icons.home_rounded, 'Home'),
    _Tab(1, Icons.checklist_rounded, Icons.checklist_rounded, 'Todo'),
    _Tab(2, Icons.chat_bubble_outline_rounded, Icons.chat_bubble_rounded, 'Chats'),
    _Tab(3, Icons.apps_rounded, Icons.apps_rounded, 'Quick', raised: true),
    _Tab(4, Icons.fingerprint_outlined, Icons.fingerprint_rounded, 'Attendance'),
    _Tab(5, Icons.account_balance_wallet_outlined, Icons.account_balance_wallet_rounded, 'Payroll'),
    _Tab(6, Icons.person_outline_rounded, Icons.person_rounded, 'Profile'),
    _Tab(7, Icons.people_alt_outlined, Icons.people_alt_rounded, 'Leads'),
  ];

  /// Bottom tabs per workspace (the user's main / chosen section), as shell-branch numbers in bar order; 3 is the raised
  /// Quick button. Sales is lead-first (Leads, Tasks, Attendance, Payroll); the others lean on what their team does most.
  /// Anything not listed — Company Admin, Administrators — gets the full default bar.
  static const _layouts = <String, List<int>>{
    'sales': [0, 7, 1, 3, 4, 5, 6],
    'marketing': [0, 2, 1, 3, 4, 6],
    'hr': [0, 4, 1, 3, 5, 2, 6],
    'accounts': [0, 1, 5, 3, 4, 2, 6],
  };
  static const _defaultLayout = [0, 1, 2, 3, 4, 5, 6];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(mobileHiddenModulesProvider); // loads the superadmin's hidden-tile list
    final cfg = ref.watch(mobileConfigProvider).maybeWhen(data: (c) => c, orElse: () => const MobileConfig());
    // Home and Profile always stay; the company can switch the rest off.
    const keyOf = {1: 'todo', 2: 'chats', 3: 'explore', 4: 'attendance', 5: 'payroll'};
    final workspace = ref.watch(activeWorkspaceProvider);
    final order = _layouts[workspace] ?? _defaultLayout;
    final canLeads = PermissionGuard.can('leads.view');
    final tabs = [
      for (final b in order)
        if ((keyOf[b] == null || cfg.tab(keyOf[b]!)) && (b != 7 || canLeads))
          workspace == 'sales' && b == 1 ? const _Tab(1, Icons.checklist_rounded, Icons.checklist_rounded, 'Tasks') : _tabs[b],
    ];
    final exploreSlot = tabs.indexWhere((t) => t.raised);
    if (PermissionGuard.teamChatEnabled) ref.watch(teamChatRealtimeProvider); // keeps the staff socket up + refreshes chats on events
    final chatUnread = PermissionGuard.teamChatEnabled ? ref.watch(teamUnreadProvider) : 0;
    PushService.instance.onOpenTeamChat = (id, mid) => context.push('/team-chat/$id${mid != null ? '?m=$mid' : ''}');
    PushService.instance.onLeadOffer = (d) => showLeadOfferDialog(context, d);
    PushService.instance.onOpenLead = (id) => context.push('/lead-detail/$id');
    PushService.instance.onOpenRoute = (r) => r == '/leads' ? context.go(r) : context.push(r);   // Leads is a bottom-bar tab: switch to it, don't stack a second shell
    final idx = navigationShell.currentIndex;
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).padding.bottom;
    const barH = 64.0, lift = 22.0;

    return Scaffold(
      body: UpdateOnOpen(child: navigationShell),   // checks for a new version once per app open
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
                  for (final t in tabs)
                    Expanded(
                      child: t.raised
                          ? const SizedBox.shrink()
                          : InkResponse(
                              // Re-tapping the current tab resets it to its initial location; a different tab
                              // just switches branch, keeping that branch's own navigation stack where it was.
                              onTap: () => navigationShell.goBranch(t.branch, initialLocation: t.branch == idx),
                              child: _item(theme, t, t.branch == idx, badge: t.branch == 2 ? chatUnread : 0),
                            ),
                    ),
                ]),
              ),
            ),
          ),
          if (exploreSlot >= 0)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              // sits over the Explore slot, wherever hidden tabs leave it
              child: Align(
                alignment: Alignment(2 * (exploreSlot + 0.5) / tabs.length - 1, 0),
                // Opens Quick access (round icon links for the current workspace); its "More" goes to the full Explore list.
                child: _raised(theme, _tabs[3], idx == 3, () => showQuickAccessSheet(context, ref, onMore: () => navigationShell.goBranch(3, initialLocation: idx == 3))),
              ),
            ),
        ]),
      ),
    );
  }

  Widget _item(ThemeData theme, _Tab t, bool selected, {int badge = 0}) {
    final color = selected ? AppColors.primary : theme.colorScheme.onSurface.withValues(alpha: 0.55);
    final icon = Icon(selected ? t.activeIcon : t.icon, size: 24, color: color);
    return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      badge > 0
          ? Badge(label: Text(badge > 99 ? '99+' : '$badge'), child: icon)
          : icon,
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
