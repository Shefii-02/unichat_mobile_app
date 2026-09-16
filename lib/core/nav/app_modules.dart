import 'package:flutter/material.dart';
import 'package:unichat_mobile_app/core/permissions/permission_guard.dart';

/// Logical grouping used on the home screen (GPay-style sections).
enum ModuleGroup {
  messaging('Messaging'),
  growth('AI & Growth'),
  sales('CRM & Sales'),
  operations('Operations'),
  account('Account');

  const ModuleGroup(this.label);
  final String label;
}

/// A single feature of the platform, surfaced as a tappable tile on the home
/// screen and wired to a route. `permission` gates visibility — `null` means
/// always visible; owners/admins see everything.
class AppModule {
  const AppModule({
    required this.id,
    required this.title,
    required this.icon,
    required this.route,
    required this.group,
    this.permission,
    this.color,
    this.subtitle,
    this.subSections = const [],
  });

  final String id;
  final String title;
  final IconData icon;
  final String route;
  final ModuleGroup group;
  final String? permission;
  final Color? color;
  final String? subtitle;
  final List<ModuleSubSection> subSections;

  bool get visible {
    if (permission == null) return true;
    return PermissionGuard.can(permission!) ||
        PermissionGuard.canView(permission!.split('.').first);
  }
}

class ModuleSubSection {
  const ModuleSubSection(this.title, this.route, {this.icon});
  final String title;
  final String route;
  final IconData? icon;
}

/// The full platform catalogue — mirrors the 25-module web blueprint.
class AppModules {
  AppModules._();

  static const List<AppModule> all = [
    // ── Messaging ────────────────────────────────────────────────
    AppModule(
      id: 'wa_chat',
      title: 'WA Chat',
      subtitle: 'Team inbox',
      icon: Icons.forum_rounded,
      route: '/chats',
      group: ModuleGroup.messaging,
      permission: 'contacts.view',
      color: Color(0xFF25D366),
    ),
    AppModule(
      id: 'wa_chat_automations',
      title: 'Automation Rules',
      subtitle: 'Auto-replies',
      icon: Icons.auto_awesome_rounded,
      route: '/wa-chat/automations',
      group: ModuleGroup.messaging,
      permission: 'wa_agent.automations.view',
      color: Color(0xFF25D366),
    ),
    AppModule(
      id: 'wa_chat_analytics',
      title: 'Inbox Analytics',
      subtitle: 'Chat volume & trends',
      icon: Icons.bar_chart_rounded,
      route: '/wa-chat/analytics',
      group: ModuleGroup.messaging,
      permission: 'contacts.view',
      color: Color(0xFF25D366),
    ),
    AppModule(
      id: 'wa_chat_audit',
      title: 'Audit Analytics',
      subtitle: 'Gateway audit trail',
      icon: Icons.fact_check_rounded,
      route: '/wa-chat/audit',
      group: ModuleGroup.messaging,
      permission: 'contacts.view',
      color: Color(0xFF25D366),
    ),
    AppModule(
      id: 'wa_cloud',
      title: 'WA Cloud',
      subtitle: 'Official API',
      icon: Icons.cloud_rounded,
      route: '/wa-cloud',
      group: ModuleGroup.messaging,
      permission: 'wa_cloud.view',
      color: Color(0xFF0EA5E9),
    ),
    AppModule(
      id: 'wa_cloud_settings',
      title: 'WA Cloud Settings',
      subtitle: 'Meta credentials',
      icon: Icons.vpn_key_rounded,
      route: '/wa-cloud/settings',
      group: ModuleGroup.messaging,
      permission: 'settings.manage',
      color: Color(0xFF0EA5E9),
    ),
    AppModule(
      id: 'wa_cloud_audit_log',
      title: 'WA Cloud Audit Log',
      subtitle: 'Webhook events',
      icon: Icons.webhook_rounded,
      route: '/wa-cloud/audit-log',
      group: ModuleGroup.messaging,
      permission: 'settings.manage',
      color: Color(0xFF0EA5E9),
    ),
    AppModule(
      id: 'message_logs',
      title: 'Message Logs',
      subtitle: 'Delivery status',
      icon: Icons.receipt_long_rounded,
      route: '/message-logs',
      group: ModuleGroup.messaging,
      color: Color(0xFF0EA5E9),
    ),
    AppModule(
      id: 'templates',
      title: 'Templates',
      subtitle: 'Message templates',
      icon: Icons.dashboard_customize_rounded,
      route: '/templates',
      group: ModuleGroup.messaging,
      permission: 'templates.view',
    ),
    AppModule(
      id: 'message_sender',
      title: 'Broadcasts',
      subtitle: 'Bulk & scheduled',
      icon: Icons.campaign_rounded,
      route: '/message-sender',
      group: ModuleGroup.messaging,
      permission: 'campaigns.view',
      color: Color(0xFFF59E0B),
    ),
    AppModule(
      id: 'phone_numbers',
      title: 'Phone Numbers',
      subtitle: 'Sessions & lines',
      icon: Icons.smartphone_rounded,
      route: '/sessions',
      group: ModuleGroup.messaging,
      permission: 'sessions.view',
    ),
    AppModule(
      id: 'flow_builder',
      title: 'Flow Builder',
      subtitle: 'Automations',
      icon: Icons.account_tree_rounded,
      route: '/flow-builder',
      group: ModuleGroup.messaging,
      permission: 'flows.view',
      color: Color(0xFF8B5CF6),
    ),

    // ── AI & Growth ──────────────────────────────────────────────
    AppModule(
      id: 'wa_agent',
      title: 'WA Agent',
      subtitle: 'AI replies',
      icon: Icons.smart_toy_rounded,
      route: '/ai-agent',
      group: ModuleGroup.growth,
      permission: 'ai_agent.view',
      color: Color(0xFF14B8A6),
    ),
    AppModule(
      id: 'ai_pipelines',
      title: 'AI Pipelines',
      subtitle: 'Multi-step workflows',
      icon: Icons.account_tree_rounded,
      route: '/wa-agent/pipelines',
      group: ModuleGroup.growth,
      permission: 'wa_agent.pipelines.view',
      color: Color(0xFF14B8A6),
    ),
    AppModule(
      id: 'lead_intelligence',
      title: 'Lead Intelligence',
      subtitle: 'AI scoring & insights',
      icon: Icons.psychology_rounded,
      route: '/wa-agent/lead-intelligence',
      group: ModuleGroup.growth,
      permission: 'ai_agent.view',
      color: Color(0xFF14B8A6),
    ),
    AppModule(
      id: 'ai_config',
      title: 'AI Config',
      subtitle: 'Analysis behavior',
      icon: Icons.settings_suggest_rounded,
      route: '/wa-agent/ai-config',
      group: ModuleGroup.growth,
      permission: 'ai_agent.view',
      color: Color(0xFF14B8A6),
    ),
    AppModule(
      id: 'wa_agent_settings',
      title: 'WA Agent Settings',
      subtitle: 'Provider & model',
      icon: Icons.tune_rounded,
      route: '/wa-agent/settings',
      group: ModuleGroup.growth,
      permission: 'wa_agent.ai.view',
      color: Color(0xFF14B8A6),
    ),
    AppModule(
      id: 'meta_ads',
      title: 'Meta Ads',
      subtitle: 'Campaign manager',
      icon: Icons.ads_click_rounded,
      route: '/meta-ads',
      group: ModuleGroup.growth,
      permission: 'meta_ads.view',
      color: Color(0xFF1877F2),
    ),
    AppModule(
      id: 'meta_lead_ads',
      title: 'Lead Ads',
      subtitle: 'Instant Form leads',
      icon: Icons.fact_check_rounded,
      route: '/meta-ads/lead-ads',
      group: ModuleGroup.growth,
      permission: 'meta_ads.view',
      color: Color(0xFF1877F2),
    ),
    AppModule(
      id: 'meta_creative_studio',
      title: 'Creative Studio',
      subtitle: 'Ad media & creatives',
      icon: Icons.brush_rounded,
      route: '/meta-ads/creative-studio',
      group: ModuleGroup.growth,
      permission: 'meta_ads.view',
      color: Color(0xFF1877F2),
    ),
    AppModule(
      id: 'instagram',
      title: 'Instagram',
      subtitle: 'DM bot & inbox',
      icon: Icons.photo_camera_rounded,
      route: '/instagram',
      group: ModuleGroup.growth,
      permission: 'instagram.view',
      color: Color(0xFFE1306C),
    ),
    AppModule(
      id: 'instagram_comments',
      title: 'Instagram Comments',
      subtitle: 'Moderate & reply',
      icon: Icons.mode_comment_rounded,
      route: '/instagram/comments',
      group: ModuleGroup.growth,
      permission: 'instagram.view',
      color: Color(0xFFE1306C),
    ),
    AppModule(
      id: 'instagram_insights',
      title: 'Instagram Insights',
      subtitle: 'Reach & engagement',
      icon: Icons.insights_rounded,
      route: '/instagram/insights',
      group: ModuleGroup.growth,
      permission: 'instagram.view',
      color: Color(0xFFE1306C),
    ),
    AppModule(
      id: 'widget',
      title: 'Chat Widget',
      subtitle: 'Website chat',
      icon: Icons.chat_bubble_rounded,
      route: '/widget',
      group: ModuleGroup.growth,
      permission: 'widget.view',
      color: Color(0xFF6366F1),
    ),
    AppModule(
      id: 'knowledge_base',
      title: 'Knowledge Base',
      subtitle: 'AI training',
      icon: Icons.menu_book_rounded,
      route: '/knowledge-base',
      group: ModuleGroup.growth,
      permission: 'ai_agent.view',
    ),
    AppModule(
      id: 'listings',
      title: 'Listings',
      subtitle: 'Products & catalog',
      icon: Icons.inventory_2_rounded,
      route: '/listings',
      group: ModuleGroup.growth,
      permission: 'listings.view',
      color: Color(0xFFEA580C),
    ),

    // ── CRM & Sales ──────────────────────────────────────────────
    AppModule(
      id: 'contacts',
      title: 'Contacts',
      subtitle: 'CRM directory',
      icon: Icons.contacts_rounded,
      route: '/contacts',
      group: ModuleGroup.sales,
      permission: 'contacts.view',
      color: Color(0xFF0F766E),
    ),
    AppModule(
      id: 'leads',
      title: 'Leads',
      subtitle: 'Pipeline',
      icon: Icons.trending_up_rounded,
      route: '/leads',
      group: ModuleGroup.sales,
      permission: 'leads.view',
      color: Color(0xFFDC2626),
    ),
    AppModule(
      id: 'lead_categories',
      title: 'Lead Categories',
      subtitle: 'Types & tags',
      icon: Icons.sell_rounded,
      route: '/lead-categories',
      group: ModuleGroup.sales,
      permission: 'leads.view',
    ),
    AppModule(
      id: 'leads_by_staff',
      title: 'Leads by Staff',
      subtitle: 'Team performance',
      icon: Icons.groups_2_rounded,
      route: '/leads-by-staff',
      group: ModuleGroup.sales,
      permission: 'staff.view',
    ),
    AppModule(
      id: 'lead_logs',
      title: 'Lead Logs',
      subtitle: 'Activity feed',
      icon: Icons.history_rounded,
      route: '/lead-logs',
      group: ModuleGroup.sales,
      permission: 'leads.view',
    ),
    AppModule(
      id: 'lead_summary',
      title: 'Lead Summary',
      subtitle: 'Dashboard',
      icon: Icons.pie_chart_rounded,
      route: '/lead-summary',
      group: ModuleGroup.sales,
      permission: 'leads.view',
    ),
    AppModule(
      id: 'lead_report',
      title: 'Lead Report',
      subtitle: 'Custom reports',
      icon: Icons.summarize_rounded,
      route: '/lead-report',
      group: ModuleGroup.sales,
      permission: 'leads.view',
    ),
    AppModule(
      id: 'assignment_queue',
      title: 'Assign Queue',
      subtitle: 'Live routing',
      icon: Icons.assignment_ind_rounded,
      route: '/assignment-queue',
      group: ModuleGroup.sales,
      permission: 'leads.view',
    ),
    AppModule(
      id: 'assignment_rules',
      title: 'Assignment Rules',
      subtitle: 'Auto-routing config',
      icon: Icons.rule_rounded,
      route: '/assignment-rules',
      group: ModuleGroup.sales,
      permission: 'lead_assignment.manage',
    ),
    AppModule(
      id: 'analytics',
      title: 'Analytics',
      subtitle: 'Reports',
      icon: Icons.insights_rounded,
      route: '/reports',
      group: ModuleGroup.sales,
      permission: 'analytics.view',
      color: Color(0xFF7C3AED),
    ),
    AppModule(
      id: 'deals',
      title: 'Deal Pipelines',
      subtitle: 'Kanban board',
      icon: Icons.handshake_rounded,
      route: '/deals',
      group: ModuleGroup.sales,
      permission: 'contacts.view',
      color: Color(0xFF0EA5E9),
    ),
    AppModule(
      id: 'crm_tasks',
      title: 'Tasks & Followups',
      subtitle: 'Team-wide',
      icon: Icons.checklist_rounded,
      route: '/crm-tasks',
      group: ModuleGroup.sales,
      permission: 'contacts.view',
    ),
    AppModule(
      id: 'calendar',
      title: 'Calendar',
      subtitle: 'Appointments',
      icon: Icons.event_rounded,
      route: '/calendar',
      group: ModuleGroup.sales,
      permission: 'contacts.view',
      color: Color(0xFF16A34A),
    ),
    AppModule(
      id: 'labels',
      title: 'Labels',
      subtitle: 'Contact tags',
      icon: Icons.label_rounded,
      route: '/labels',
      group: ModuleGroup.sales,
      permission: 'contacts.view',
    ),
    AppModule(
      id: 'segments',
      title: 'Segments',
      subtitle: 'Audience filters',
      icon: Icons.filter_alt_rounded,
      route: '/segments',
      group: ModuleGroup.sales,
      permission: 'contacts.view',
    ),
    AppModule(
      id: 'blacklist',
      title: 'Blacklist',
      subtitle: 'Blocked numbers',
      icon: Icons.block_rounded,
      route: '/blacklist',
      group: ModuleGroup.sales,
      permission: 'contacts.view',
      color: Color(0xFFDC2626),
    ),
    AppModule(
      id: 'survey_forms',
      title: 'Survey Forms',
      subtitle: 'Lead capture',
      icon: Icons.assignment_rounded,
      route: '/forms',
      group: ModuleGroup.sales,
      permission: 'forms.view',
    ),

    // ── Operations ───────────────────────────────────────────────
    AppModule(
      id: 'staff',
      title: 'Staff & Roles',
      subtitle: 'Team access',
      icon: Icons.groups_rounded,
      route: '/staff',
      group: ModuleGroup.operations,
      permission: 'staff.view',
    ),
    AppModule(
      id: 'hr',
      title: 'HR',
      subtitle: 'Attendance & payroll',
      icon: Icons.badge_rounded,
      route: '/hr',
      group: ModuleGroup.operations,
      permission: 'hr.view',
    ),
    AppModule(
      id: 'media_library',
      title: 'Media Library',
      subtitle: 'Files & folders',
      icon: Icons.perm_media_rounded,
      route: '/media-library',
      group: ModuleGroup.operations,
      permission: 'media.view',
    ),
    AppModule(
      id: 'otp_service',
      title: 'OTP / API',
      subtitle: 'Developer service',
      icon: Icons.vpn_key_rounded,
      route: '/otp-service',
      group: ModuleGroup.operations,
      permission: 'otp.view',
    ),
    AppModule(
      id: 'export',
      title: 'Export',
      subtitle: 'Data export',
      icon: Icons.ios_share_rounded,
      route: '/export',
      group: ModuleGroup.operations,
      permission: 'export.view',
    ),
    AppModule(
      id: 'integrations',
      title: 'Integrations',
      subtitle: 'Sheets, Drive & more',
      icon: Icons.extension_rounded,
      route: '/integrations',
      group: ModuleGroup.operations,
      permission: 'integrations.view',
    ),

    // ── Account ──────────────────────────────────────────────────
    AppModule(
      id: 'setup_guide',
      title: 'Setup Guide',
      subtitle: 'Get started',
      icon: Icons.checklist_rounded,
      route: '/setup-guide',
      group: ModuleGroup.account,
    ),
    AppModule(
      id: 'wallet',
      title: 'Wallet & Plans',
      subtitle: 'Billing',
      icon: Icons.account_balance_wallet_rounded,
      route: '/wallet',
      group: ModuleGroup.account,
      permission: 'billing.view',
      color: Color(0xFF16A34A),
    ),
    AppModule(
      id: 'devices',
      title: 'Devices',
      subtitle: 'Linked devices',
      icon: Icons.devices_rounded,
      route: '/devices',
      group: ModuleGroup.account,
    ),
    AppModule(
      id: 'settings',
      title: 'Settings',
      subtitle: 'Preferences',
      icon: Icons.settings_rounded,
      route: '/settings',
      group: ModuleGroup.account,
    ),
    AppModule(
      id: 'superadmin',
      title: 'SuperAdmin',
      subtitle: 'Platform control',
      icon: Icons.shield_rounded,
      route: '/superadmin',
      group: ModuleGroup.account,
      permission: 'platform.manage',
      color: Color(0xFFB91C1C),
    ),
  ];

  static List<AppModule> visibleFor(ModuleGroup group) =>
      all.where((m) => m.group == group && m.visible).toList();

  static List<ModuleGroup> get groupsWithContent => ModuleGroup.values
      .where((g) => visibleFor(g).isNotEmpty)
      .toList();

  static AppModule? byRoute(String route) {
    for (final m in all) {
      if (m.route == route) return m;
    }
    return null;
  }
}
