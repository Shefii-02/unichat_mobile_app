import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:unichat_mobile_app/core/nav/app_modules.dart';
import 'package:unichat_mobile_app/core/router/shell_routes.dart';
import 'package:unichat_mobile_app/features/workspace/workspace_provider.dart';

class _Action {
  const _Action(this.icon, this.label, this.route, this.color);
  final IconData icon;
  final String label, route;
  final Color color;
}

const _indigo = Color(0xFF4F46E5);
const _blue = Color(0xFF2563EB);
const _green = Color(0xFF15803D);
const _orange = Color(0xFFEA580C);
const _pink = Color(0xFFBE185D);
const _teal = Color(0xFF0F766E);
const _amber = Color(0xFFB45309);
const _slate = Color(0xFF334155);
const _red = Color(0xFFDC2626);

/// Quick-access actions per workspace. Anything the user's role or plan doesn't allow is dropped when the sheet opens.
const _actions = <String, List<_Action>>{
  'company_admin': [
    _Action(Icons.person_add_alt_1_rounded, 'Add lead', '/leads', _indigo),
    _Action(Icons.contacts_outlined, 'Contacts', '/contacts', _blue),
    _Action(Icons.checklist_rounded, 'Tasks', '/crm-tasks', _orange),
    _Action(Icons.chat_outlined, 'Chats', '/wa-chat/chats', _green),
    _Action(Icons.fingerprint_rounded, 'Attendance', '/attendance', _teal),
    _Action(Icons.groups_outlined, 'Staff', '/staff', _slate),
    _Action(Icons.bar_chart_rounded, 'Reports', '/reports', _pink),
    _Action(Icons.account_balance_wallet_outlined, 'Wallet', '/wallet', _amber),
  ],
  'sales': [
    _Action(Icons.person_add_alt_1_rounded, 'Add lead', '/leads', _indigo),
    _Action(Icons.contacts_outlined, 'Contacts', '/contacts', _blue),
    _Action(Icons.timer_outlined, 'Follow-ups', '/crm-followups', _red),
    _Action(Icons.chat_outlined, 'WhatsApp', '/wa-chat/chats', _green),
    _Action(Icons.layers_outlined, 'Deals', '/deals', _orange),
    _Action(Icons.checklist_rounded, 'Tasks', '/crm-tasks', _teal),
    _Action(Icons.event_outlined, 'Calendar', '/calendar', _pink),
    _Action(Icons.summarize_outlined, 'Lead report', '/lead-report', _slate),
  ],
  'administrators': [
    _Action(Icons.groups_outlined, 'Staff', '/staff', _blue),
    _Action(Icons.shield_outlined, 'Roles', '/account/roles', _indigo),
    _Action(Icons.smartphone_rounded, 'Devices', '/devices', _orange),
    _Action(Icons.power_outlined, 'Integrations', '/integrations', _red),
    _Action(Icons.settings_outlined, 'Settings', '/settings', _slate),
    _Action(Icons.workspace_premium_outlined, 'Plan', '/account/plan-billing', _amber),
    _Action(Icons.account_balance_wallet_outlined, 'Wallet', '/wallet', _green),
    _Action(Icons.menu_book_outlined, 'Setup guide', '/setup-guide', _teal),
  ],
  'hr': [
    _Action(Icons.schedule_rounded, 'Attendance', '/hr/attendance-all', _teal),
    _Action(Icons.event_available_outlined, 'Leave', '/hr/leave-requests', _orange),
    _Action(Icons.payments_outlined, 'Payroll', '/hr/payrolls', _indigo),
    _Action(Icons.badge_outlined, 'Staff setup', '/hr/staff-setup', _blue),
    _Action(Icons.card_giftcard_rounded, 'Incentives', '/hr/incentives', _pink),
    _Action(Icons.receipt_long_outlined, 'Sales', '/hr/sales', _green),
    _Action(Icons.coffee_outlined, 'Break types', '/hr/break-types', _amber),
    _Action(Icons.apartment_rounded, 'Office', '/hr/office', _slate),
  ],
  'marketing': [
    _Action(Icons.campaign_outlined, 'Ad campaigns', '/meta-ads/campaigns', _pink),
    _Action(Icons.send_rounded, 'WA campaigns', '/wa-chat/message-sender', _green),
    _Action(Icons.description_outlined, 'Templates', '/wa-cloud/templates', _indigo),
    _Action(Icons.account_tree_outlined, 'Flows', '/instagram/automations', _teal),
    _Action(Icons.camera_alt_outlined, 'Social inbox', '/instagram', _red),
    _Action(Icons.brush_outlined, 'Creative studio', '/meta-ads/creative-studio', _orange),
    _Action(Icons.ads_click_rounded, 'Lead ads', '/meta-ads/lead-ads', _blue),
    _Action(Icons.perm_media_outlined, 'Media', '/media-library', _slate),
  ],
  'accounts': [
    _Action(Icons.menu_book_outlined, 'Books', '/accounts', _amber),
    _Action(Icons.account_balance_wallet_outlined, 'Wallet', '/wallet', _green),
    _Action(Icons.workspace_premium_outlined, 'Plan & billing', '/account/plan-billing', _indigo),
    _Action(Icons.payments_outlined, 'Payroll', '/hr/payrolls', _teal),
    _Action(Icons.file_download_outlined, 'Export', '/export', _blue),
    _Action(Icons.bar_chart_rounded, 'Reports', '/reports', _pink),
    _Action(Icons.summarize_outlined, 'Lead summary', '/lead-summary', _slate),
    _Action(Icons.receipt_long_outlined, 'Invoices', '/accounts', _orange),
  ],
};

/// The centre button of the bottom bar: a Quick access sheet — a grid of round icon links for the workspace the user is in, plus "More"
/// (the full Explore list). Role- and plan-restricted links are left out.
Future<void> showQuickAccessSheet(BuildContext context, WidgetRef ref, {required VoidCallback onMore}) {
  final workspace = ref.read(activeWorkspaceProvider) ?? 'company_admin';
  final title = workspaceByKey(workspace)?.title ?? 'Company Admin';
  final items = [
    for (final a in _actions[workspace] ?? _actions['company_admin']!)
      if (AppModules.byRoute(a.route)?.visible != false) a,
  ].take(7).toList();

  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      Widget circle(IconData icon, String label, Color color, VoidCallback onTap, {bool outlined = false}) => GestureDetector(
            onTap: onTap,
            behavior: HitTestBehavior.opaque,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 58, height: 58,
                decoration: BoxDecoration(shape: BoxShape.circle, color: outlined ? Colors.transparent : color.withValues(alpha: 0.14), border: outlined ? Border.all(color: theme.dividerColor, width: 1.5) : null),
                child: Icon(icon, color: outlined ? theme.colorScheme.onSurface.withValues(alpha: 0.7) : color, size: 26),
              ),
              const SizedBox(height: 8),
              Text(label, maxLines: 2, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, height: 1.15)),
            ]),
          );

      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Quick access', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            Text(title, style: TextStyle(fontSize: 12.5, color: theme.colorScheme.onSurface.withValues(alpha: 0.6))),
            const SizedBox(height: 16),
            GridView.count(
              crossAxisCount: 4,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 16,
              crossAxisSpacing: 8,
              childAspectRatio: 0.82,
              children: [
                for (final a in items) circle(a.icon, a.label, a.color, () { Navigator.pop(ctx); context.goToRoute(a.route); }),
                circle(Icons.grid_view_rounded, 'More', _slate, () { Navigator.pop(ctx); onMore(); }, outlined: true),
              ],
            ),
          ]),
        ),
      );
    },
  );
}
