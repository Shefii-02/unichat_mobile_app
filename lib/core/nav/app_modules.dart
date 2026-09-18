import 'package:flutter/material.dart';
import 'package:unichat_mobile_app/core/permissions/permission_guard.dart';

/// Logical grouping used on the home screen and Quick Actions (GPay-style sections) — split
/// finely enough that each section is one recognisable product area (WA Chat vs WA Cloud vs
/// WA Agents are three separate teams' worth of features even though they all touch
/// WhatsApp), rather than lumping everything WhatsApp-shaped into one "Messaging" bucket.
enum ModuleGroup {
  waChat('WA Chat'),
  waCloud('WA Cloud'),
  waAgents('WA Agents'),
  metaInstagram('Meta Ads & Instagram'),
  sales('CRM & Leads'),
  hr('HR'),
  operations('Operations'),
  account('Account');

  const ModuleGroup(this.label);
  final String label;
}

/// A single feature of the platform, surfaced as a tappable tile on the home
/// screen and wired to a route. `permission` gates visibility — `null` means
/// always visible; owners/admins see everything. A company/role that lacks a
/// tile's permission never sees it, and a whole section header disappears on
/// its own once none of its tiles are visible (see [AppModules.groupsWithContent])
/// — so as a company's enabled features change over time, the catalogue always
/// reflects exactly what that company can actually use, with no extra code needed
/// per company.
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
///
/// Every tile's [AppModule.color] is drawn from one shared ~15-colour palette, assigned by
/// what the feature *does* (communication = blue/green, analytics = amber, automation/AI =
/// indigo, logs/settings/utility = gray, money = teal/maroon, danger/blocking = red, and so
/// on) — not one flat colour per whole section. Two unrelated features can still land on the
/// same colour if they're the same kind of thing (e.g. every "logs" screen is gray); that's
/// intentional, not a leftover copy-paste.
///
/// Each section's item list and order below matches the approved design spec exactly —
/// resist adding extra tiles to a section on your own initiative; anything not in that spec
/// but still worth surfacing goes in Operations instead (see Flow Builder, Analytics, Lead
/// Summary below).
class AppModules {
  AppModules._();

  static const List<AppModule> all = [
    // ── WA Chat: Dashboard, Sessions, Chats, Campaigns, Templates, API Services, Media
    // Library, Automation, Inbox Analytics, Audit Analytics, Export ─────────────────
    AppModule(
      id: 'wa_chat_dashboard',
      title: 'Dashboard',
      subtitle: 'Sessions & message stats',
      icon: Icons.dashboard_rounded,
      route: '/wa-chat/dashboard',
      group: ModuleGroup.waChat,
      permission: 'sessions.view',
      color: Color(0xFF0F766E),
    ),
    AppModule(
      id: 'phone_numbers',
      title: 'Sessions',
      subtitle: 'Devices & lines',
      icon: Icons.smartphone_rounded,
      route: '/wa-chat/sessions',
      group: ModuleGroup.waChat,
      permission: 'sessions.view',
      color: Color(0xFF2E9CCA),
    ),
    AppModule(
      id: 'wa_chat',
      title: 'Chats',
      subtitle: 'Team inbox',
      icon: Icons.forum_rounded,
      route: '/wa-chat/chats',
      group: ModuleGroup.waChat,
      permission: 'contacts.view',
      color: Color(0xFF25D366),
    ),
    AppModule(
      id: 'message_sender',
      title: 'Campaigns',
      subtitle: 'Bulk & scheduled',
      icon: Icons.campaign_rounded,
      route: '/wa-chat/message-sender',
      group: ModuleGroup.waChat,
      permission: 'campaigns.view',
      color: Color(0xFFF5871F),
    ),
    AppModule(
      id: 'templates',
      title: 'Templates',
      subtitle: 'Message templates',
      icon: Icons.dashboard_customize_rounded,
      route: '/wa-chat/templates',
      group: ModuleGroup.waChat,
      permission: 'templates.view',
      color: Color(0xFF8A5CF6),
    ),
    AppModule(
      id: 'wa_chat_api_services',
      title: 'API Services',
      subtitle: 'Developer service',
      icon: Icons.vpn_key_rounded,
      route: '/otp-service',
      group: ModuleGroup.waChat,
      permission: 'otp.view',
      color: Color(0xFFE0475B),
    ),
    AppModule(
      id: 'wa_chat_media_library',
      title: 'Media Library',
      subtitle: 'Files & folders',
      icon: Icons.perm_media_rounded,
      route: '/media-library',
      group: ModuleGroup.waChat,
      permission: 'media.view',
      color: Color(0xFF12A594),
    ),
    AppModule(
      id: 'wa_chat_automations',
      title: 'Automation',
      subtitle: 'Auto-replies',
      icon: Icons.auto_awesome_rounded,
      route: '/wa-chat/automations',
      group: ModuleGroup.waChat,
      permission: 'wa_agent.automations.view',
      color: Color(0xFF6D5EF0),
    ),
    AppModule(
      id: 'wa_chat_analytics',
      title: 'Inbox Analytics',
      subtitle: 'Chat volume & trends',
      icon: Icons.bar_chart_rounded,
      route: '/wa-chat/analytics',
      group: ModuleGroup.waChat,
      permission: 'contacts.view',
      color: Color(0xFFDB8A19),
    ),
    AppModule(
      id: 'wa_chat_audit',
      title: 'Audit Logs',
      subtitle: 'Gateway audit trail',
      icon: Icons.fact_check_rounded,
      route: '/wa-chat/audit',
      group: ModuleGroup.waChat,
      permission: 'contacts.view',
      color: Color(0xFF5C6570),
    ),
    AppModule(
      id: 'wa_chat_export',
      title: 'Export',
      subtitle: 'Chats, contacts & groups to CSV',
      icon: Icons.download_rounded,
      route: '/wa-chat/export',
      group: ModuleGroup.waChat,
      permission: 'reports.manage',
      color: Color(0xFF64748B),
    ),

    // ── WA Cloud: Phone Numbers, WA Templates, Survey Forms, API Services,
    // Agent Automations, Inbox, Settings, Inbox Analytics, Audit Logs, Message Logs ──
    AppModule(
      id: 'cloud_numbers',
      title: 'Phone Numbers',
      subtitle: 'Official API lines',
      icon: Icons.dialpad_rounded,
      route: '/wa-cloud/phone-numbers',
      group: ModuleGroup.waCloud,
      permission: 'sessions.view',
      color: Color(0xFF2E9CCA),
    ),
    AppModule(
      id: 'wa_cloud_templates',
      title: 'WA Templates',
      subtitle: 'Message templates',
      icon: Icons.dashboard_customize_rounded,
      route: '/wa-cloud/templates',
      group: ModuleGroup.waCloud,
      permission: 'templates.view',
      color: Color(0xFF8A5CF6),
    ),
    AppModule(
      id: 'wa_cloud_survey_forms',
      title: 'Survey Forms',
      subtitle: 'Lead capture',
      icon: Icons.assignment_rounded,
      route: '/forms',
      group: ModuleGroup.waCloud,
      permission: 'forms.view',
      color: Color(0xFFDB4C6A),
    ),
    AppModule(
      id: 'wa_cloud_api_services',
      title: 'API Services',
      subtitle: 'Developer service',
      icon: Icons.vpn_key_rounded,
      route: '/wa-cloud/otp-service',
      group: ModuleGroup.waCloud,
      permission: 'wa_cloud.view',
      color: Color(0xFFE0475B),
    ),
    AppModule(
      id: 'wa_cloud_automations',
      title: 'Agent Automations',
      subtitle: 'Auto-replies',
      icon: Icons.auto_awesome_rounded,
      route: '/wa-cloud/automations',
      group: ModuleGroup.waCloud,
      permission: 'wa_cloud.view',
      color: Color(0xFF6D5EF0),
    ),
    AppModule(
      id: 'wa_cloud_inbox',
      title: 'Inbox',
      subtitle: 'Team inbox',
      icon: Icons.inbox_rounded,
      route: '/wa-chat/chats',
      group: ModuleGroup.waCloud,
      permission: 'contacts.view',
      color: Color(0xFF25A9E0),
    ),
    AppModule(
      id: 'wa_cloud_settings',
      title: 'Settings',
      subtitle: 'Meta credentials',
      icon: Icons.vpn_key_rounded,
      route: '/wa-cloud/settings',
      group: ModuleGroup.waCloud,
      permission: 'settings.manage',
      color: Color(0xFF5C6570),
    ),
    AppModule(
      id: 'wa_cloud',
      title: 'Inbox Analytics',
      subtitle: 'Chat volume & trends',
      icon: Icons.bar_chart_rounded,
      route: '/wa-cloud',
      group: ModuleGroup.waCloud,
      permission: 'wa_cloud.view',
      color: Color(0xFFDB8A19),
    ),
    AppModule(
      id: 'wa_cloud_audit_log',
      title: 'Audit Logs',
      subtitle: 'Webhook events',
      icon: Icons.webhook_rounded,
      route: '/wa-cloud/audit-log',
      group: ModuleGroup.waCloud,
      permission: 'settings.manage',
      color: Color(0xFF5C6570),
    ),
    AppModule(
      id: 'message_logs',
      title: 'Message Logs',
      subtitle: 'Delivery status',
      icon: Icons.receipt_long_rounded,
      route: '/message-logs',
      group: ModuleGroup.waCloud,
      color: Color(0xFF12A594),
    ),

    // ── WA Agents: Knowledge Base, Pipelines, AI Agents, Playbooks, Lead Intelligence,
    // AI Config, Logs, Settings ────────────────────────────────────
    AppModule(
      id: 'knowledge_base',
      title: 'Knowledge Base',
      subtitle: 'AI training',
      icon: Icons.menu_book_rounded,
      route: '/knowledge-base',
      group: ModuleGroup.waAgents,
      permission: 'ai_agent.view',
      color: Color(0xFF7C5CFC),
    ),
    AppModule(
      id: 'ai_pipelines',
      title: 'Pipelines',
      subtitle: 'Multi-step workflows',
      icon: Icons.account_tree_rounded,
      route: '/wa-agent/pipelines',
      group: ModuleGroup.waAgents,
      permission: 'wa_agent.pipelines.view',
      color: Color(0xFF0EA5A5),
    ),
    AppModule(
      id: 'wa_agent_ai_agents',
      title: 'AI Agents',
      subtitle: 'AI replies',
      icon: Icons.smart_toy_rounded,
      route: '/ai-agent',
      group: ModuleGroup.waAgents,
      permission: 'ai_agent.view',
      color: Color(0xFF14B8A6),
    ),
    AppModule(
      id: 'wa_agent_playbooks',
      title: 'Playbooks',
      subtitle: 'Guided conversation scripts',
      icon: Icons.article_rounded,
      route: '/wa-agent/playbooks',
      group: ModuleGroup.waAgents,
      permission: 'ai_agent.view',
      color: Color(0xFFDB8A19),
    ),
    AppModule(
      id: 'lead_intelligence',
      title: 'Lead Intelligence',
      subtitle: 'AI scoring & insights',
      icon: Icons.psychology_rounded,
      route: '/wa-agent/lead-intelligence',
      group: ModuleGroup.waAgents,
      permission: 'ai_agent.view',
      color: Color(0xFFE0475B),
    ),
    AppModule(
      id: 'ai_config',
      title: 'AI Config',
      subtitle: 'Analysis behavior',
      icon: Icons.settings_suggest_rounded,
      route: '/wa-agent/ai-config',
      group: ModuleGroup.waAgents,
      permission: 'ai_agent.view',
      color: Color(0xFF5C6570),
    ),
    AppModule(
      id: 'wa_agent_logs',
      title: 'Logs',
      subtitle: 'Automation rule executions',
      icon: Icons.history_rounded,
      route: '/wa-agent/logs',
      group: ModuleGroup.waAgents,
      permission: 'wa_agent.automations.view',
      color: Color(0xFF5C6570),
    ),
    // Same /listings catalog as the 'listings' module above (Meta Ads/Instagram group) — the
    // AI agent answers about and matches leads against this one company-wide catalog, so it's
    // surfaced here too rather than duplicated as a separate feature.
    AppModule(
      id: 'wa_agent_catalog',
      title: 'Catalog',
      subtitle: 'Listings & products',
      icon: Icons.inventory_2_rounded,
      route: '/listings',
      group: ModuleGroup.waAgents,
      permission: 'catalog.view',
      color: Color(0xFFEA580C),
    ),
    AppModule(
      id: 'wa_agent_settings',
      title: 'Settings',
      subtitle: 'Provider & model',
      icon: Icons.tune_rounded,
      route: '/wa-agent/settings',
      group: ModuleGroup.waAgents,
      permission: 'wa_agent.ai.view',
      color: Color(0xFF5C6570),
    ),

    // ── Meta Ads & Instagram: Accounts, Campaign, Audience Set, Lead Ads,
    // Creative Studio, Media Library, Ads Insight, Auto DM Rules, SM Inbox, Comments,
    // Insight, Catalogs ────────────────────────────────────────────
    AppModule(
      id: 'meta_accounts',
      title: 'Accounts',
      subtitle: 'Connected ad accounts',
      icon: Icons.account_circle_rounded,
      route: '/meta-ads/accounts',
      group: ModuleGroup.metaInstagram,
      permission: 'meta_ads.view',
      color: Color(0xFF1877F2),
    ),
    AppModule(
      id: 'meta_campaigns',
      title: 'Campaign',
      subtitle: 'Ad campaigns',
      icon: Icons.campaign_rounded,
      route: '/meta-ads/campaigns',
      group: ModuleGroup.metaInstagram,
      permission: 'meta_ads.view',
      color: Color(0xFFF5871F),
    ),
    AppModule(
      id: 'meta_audience_sets',
      title: 'Audience Set',
      subtitle: 'Targeting groups',
      icon: Icons.groups_2_rounded,
      route: '/meta-ads/audience-sets',
      group: ModuleGroup.metaInstagram,
      permission: 'meta_ads.view',
      color: Color(0xFF0EA5A5),
    ),
    AppModule(
      id: 'meta_lead_ads',
      title: 'Lead Ads',
      subtitle: 'Instant Form leads',
      icon: Icons.fact_check_rounded,
      route: '/meta-ads/lead-ads',
      group: ModuleGroup.metaInstagram,
      permission: 'meta_ads.view',
      color: Color(0xFFDB4C6A),
    ),
    AppModule(
      id: 'meta_creative_studio',
      title: 'Creative Studio',
      subtitle: 'Ad media & creatives',
      icon: Icons.brush_rounded,
      route: '/meta-ads/creative-studio',
      group: ModuleGroup.metaInstagram,
      permission: 'meta_ads.view',
      color: Color(0xFF8A5CF6),
    ),
    AppModule(
      id: 'meta_media_library',
      title: 'Media Library',
      subtitle: 'Files & folders',
      icon: Icons.perm_media_rounded,
      route: '/media-library',
      group: ModuleGroup.metaInstagram,
      permission: 'media.view',
      color: Color(0xFF12A594),
    ),
    AppModule(
      id: 'meta_ads',
      title: 'Ads Insight',
      subtitle: 'Performance overview',
      icon: Icons.ads_click_rounded,
      route: '/meta-ads',
      group: ModuleGroup.metaInstagram,
      permission: 'meta_ads.view',
      color: Color(0xFF1877F2),
    ),
    AppModule(
      id: 'instagram_automations',
      title: 'Auto DM Rules',
      subtitle: 'Comment & DM automation',
      icon: Icons.smart_toy_rounded,
      route: '/instagram/automations',
      group: ModuleGroup.metaInstagram,
      permission: 'instagram.view',
      color: Color(0xFFDD2A7B),
    ),
    AppModule(
      id: 'instagram',
      title: 'SM Inbox',
      subtitle: 'DM bot & inbox',
      icon: Icons.photo_camera_rounded,
      route: '/instagram',
      group: ModuleGroup.metaInstagram,
      permission: 'instagram.view',
      color: Color(0xFFDD2A7B),
    ),
    AppModule(
      id: 'instagram_comments',
      title: 'Comments',
      subtitle: 'Moderate & reply',
      icon: Icons.mode_comment_rounded,
      route: '/instagram/comments',
      group: ModuleGroup.metaInstagram,
      permission: 'instagram.view',
      color: Color(0xFFDD2A7B),
    ),
    AppModule(
      id: 'instagram_insights',
      title: 'Insight',
      subtitle: 'Reach & engagement',
      icon: Icons.insights_rounded,
      route: '/instagram/insights',
      group: ModuleGroup.metaInstagram,
      permission: 'instagram.view',
      color: Color(0xFFDD2A7B),
    ),
    AppModule(
      id: 'listings',
      title: 'Catalogs',
      subtitle: 'Products & catalog',
      icon: Icons.inventory_2_rounded,
      route: '/listings',
      group: ModuleGroup.metaInstagram,
      permission: 'catalog.view',
      color: Color(0xFFEA580C),
    ),

    // ── CRM & Leads: All Contacts, Labels, Deal Pipelines, Tasks/Follow-ups, Calendar,
    // Segments, Black List, All Leads, Lead Category, Lead by Staff, Lead Logs,
    // Lead Report, Assign Queues, Assignment Rules ─────────────────
    AppModule(
      id: 'contacts',
      title: 'All Contacts',
      subtitle: 'CRM directory',
      icon: Icons.contacts_rounded,
      route: '/contacts',
      group: ModuleGroup.sales,
      permission: 'contacts.view',
      color: Color(0xFF6D5EF0),
    ),
    AppModule(
      id: 'labels',
      title: 'Labels',
      subtitle: 'Contact tags',
      icon: Icons.label_rounded,
      route: '/labels',
      group: ModuleGroup.sales,
      permission: 'contacts.view',
      color: Color(0xFFDB8A19),
    ),
    AppModule(
      id: 'deals',
      title: 'Deal Pipelines',
      subtitle: 'Kanban board',
      icon: Icons.handshake_rounded,
      route: '/deals',
      group: ModuleGroup.sales,
      permission: 'contacts.view',
      color: Color(0xFF0EA5A5),
    ),
    AppModule(
      id: 'crm_tasks',
      title: 'Tasks/Follow-ups',
      subtitle: 'Team-wide',
      icon: Icons.checklist_rounded,
      route: '/crm-tasks',
      group: ModuleGroup.sales,
      permission: 'contacts.view',
      color: Color(0xFFE0475B),
    ),
    AppModule(
      id: 'calendar',
      title: 'Calendar',
      subtitle: 'Appointments',
      icon: Icons.event_rounded,
      route: '/calendar',
      group: ModuleGroup.sales,
      permission: 'contacts.view',
      color: Color(0xFF2E9CCA),
    ),
    AppModule(
      id: 'segments',
      title: 'Segments',
      subtitle: 'Audience filters',
      icon: Icons.filter_alt_rounded,
      route: '/segments',
      group: ModuleGroup.sales,
      permission: 'contacts.view',
      color: Color(0xFF8A5CF6),
    ),
    AppModule(
      id: 'blacklist',
      title: 'Black List',
      subtitle: 'Blocked numbers',
      icon: Icons.block_rounded,
      route: '/blacklist',
      group: ModuleGroup.sales,
      permission: 'contacts.view',
      color: Color(0xFF5C6570),
    ),
    AppModule(
      id: 'leads',
      title: 'All Leads',
      subtitle: 'Pipeline',
      icon: Icons.trending_up_rounded,
      route: '/leads',
      group: ModuleGroup.sales,
      permission: 'leads.view',
      color: Color(0xFFDB4C6A),
    ),
    AppModule(
      id: 'lead_categories',
      title: 'Lead Category',
      subtitle: 'Types & tags',
      icon: Icons.sell_rounded,
      route: '/lead-categories',
      group: ModuleGroup.sales,
      permission: 'leads.view',
      color: Color(0xFFDB8A19),
    ),
    AppModule(
      id: 'leads_by_staff',
      title: 'Lead by Staff',
      subtitle: 'Team performance',
      icon: Icons.groups_2_rounded,
      route: '/leads-by-staff',
      group: ModuleGroup.sales,
      permission: 'staff.view',
      color: Color(0xFF0EA5A5),
    ),
    AppModule(
      id: 'lead_logs',
      title: 'Lead Logs',
      subtitle: 'Activity feed',
      icon: Icons.history_rounded,
      route: '/lead-logs',
      group: ModuleGroup.sales,
      permission: 'leads.view',
      color: Color(0xFF5C6570),
    ),
    AppModule(
      id: 'lead_report',
      title: 'Lead Report',
      subtitle: 'Custom reports',
      icon: Icons.summarize_rounded,
      route: '/lead-report',
      group: ModuleGroup.sales,
      permission: 'leads.view',
      color: Color(0xFF6D5EF0),
    ),
    AppModule(
      id: 'assignment_queue',
      title: 'Assign Queues',
      subtitle: 'Live routing',
      icon: Icons.assignment_ind_rounded,
      route: '/assignment-queue',
      group: ModuleGroup.sales,
      permission: 'leads.view',
      color: Color(0xFFF5871F),
    ),
    AppModule(
      id: 'assignment_rules',
      title: 'Assignment Rules',
      subtitle: 'Auto-routing config',
      icon: Icons.rule_rounded,
      route: '/assignment-rules',
      group: ModuleGroup.sales,
      permission: 'lead_assignment.manage',
      color: Color(0xFFDB4C6A),
    ),

    // ── HR: My Attendance, My Target, My Payroll, Attendances (All), Payrolls, Sales,
    // Incentives, Leave Requests, Staff Setups, Break Types, Leave Types, Office Details ──
    // My Attendance/Target/Payroll point at the same bottom-nav tab roots as the
    // Attendance/Target/Payroll tabs themselves (goToRoute switches tabs for these instead
    // of pushing a duplicate shell — see shell_routes.dart). Self-service, so no permission
    // gate, matching the tabs' own always-visible behaviour. The rest each have their own
    // dedicated page under `/hr/...` (see lib/features/hr/presentation/pages/).
    AppModule(
      id: 'my_attendance',
      title: 'My Attendance',
      subtitle: 'Clock in/out',
      icon: Icons.fingerprint_rounded,
      route: '/attendance',
      group: ModuleGroup.hr,
      color: Color(0xFF0C447C),
    ),
    AppModule(
      id: 'my_target',
      title: 'My Target',
      subtitle: 'Sales progress',
      icon: Icons.track_changes_rounded,
      route: '/target',
      group: ModuleGroup.hr,
      color: Color(0xFF27500A),
    ),
    AppModule(
      id: 'my_payroll',
      title: 'My Payroll',
      subtitle: 'Payslips',
      icon: Icons.account_balance_wallet_rounded,
      route: '/payroll',
      group: ModuleGroup.hr,
      color: Color(0xFF72243E),
    ),
    AppModule(
      id: 'hr_attendance_all',
      title: 'Attendances (All)',
      subtitle: "Team's daily attendance",
      icon: Icons.groups_rounded,
      route: '/hr/attendance-all',
      group: ModuleGroup.hr,
      permission: 'hr.view',
      color: Color(0xFF0C447C),
    ),
    AppModule(
      id: 'hr_payrolls',
      title: 'Payrolls',
      subtitle: 'Team payroll runs',
      icon: Icons.payments_rounded,
      route: '/hr/payrolls',
      group: ModuleGroup.hr,
      permission: 'hr.view',
      color: Color(0xFF72243E),
    ),
    AppModule(
      id: 'hr_sales',
      title: 'Sales',
      subtitle: 'Team sales records',
      icon: Icons.trending_up_rounded,
      route: '/hr/sales',
      group: ModuleGroup.hr,
      permission: 'hr.view',
      color: Color(0xFF27500A),
    ),
    AppModule(
      id: 'hr_incentives',
      title: 'Incentives',
      subtitle: 'Bonus rules',
      icon: Icons.card_giftcard_rounded,
      route: '/hr/incentives',
      group: ModuleGroup.hr,
      permission: 'hr.view',
      color: Color(0xFF854F0B),
    ),
    AppModule(
      id: 'hr_leave_requests',
      title: 'Leave Requests',
      subtitle: 'Approve / reject',
      icon: Icons.event_busy_rounded,
      route: '/hr/leave-requests',
      group: ModuleGroup.hr,
      permission: 'hr.view',
      color: Color(0xFF993C1D),
    ),
    AppModule(
      id: 'hr_staff_setup',
      title: 'Staff Setups',
      subtitle: 'Per-staff HR profile',
      icon: Icons.manage_accounts_rounded,
      route: '/hr/staff-setup',
      group: ModuleGroup.hr,
      permission: 'hr.view',
      color: Color(0xFF3C3489),
    ),
    AppModule(
      id: 'hr_break_types',
      title: 'Break Types',
      subtitle: 'Configure breaks',
      icon: Icons.free_breakfast_rounded,
      route: '/hr/break-types',
      group: ModuleGroup.hr,
      permission: 'hr.view',
      color: Color(0xFF5C6570),
    ),
    AppModule(
      id: 'hr_leave_types',
      title: 'Leave Types',
      subtitle: 'Configure leave',
      icon: Icons.flight_takeoff_rounded,
      route: '/hr/leave-types',
      group: ModuleGroup.hr,
      permission: 'hr.view',
      color: Color(0xFF5C6570),
    ),
    AppModule(
      id: 'hr_office',
      title: 'Office Details',
      subtitle: 'Hours, geofence & rules',
      icon: Icons.business_rounded,
      route: '/hr/office',
      group: ModuleGroup.hr,
      permission: 'hr.view',
      color: Color(0xFF5C6570),
    ),

    // ── Account: Staffs, Roles, Account Access, Wallet, Plan Billing, Setup Guides ──
    AppModule(
      id: 'staff',
      title: 'Staffs',
      subtitle: 'Team access',
      icon: Icons.groups_rounded,
      route: '/staff',
      group: ModuleGroup.account,
      permission: 'staff.view',
      color: Color(0xFF3C3489),
    ),
    AppModule(
      id: 'roles',
      title: 'Roles',
      subtitle: 'Permission sets',
      icon: Icons.shield_moon_rounded,
      route: '/account/roles',
      group: ModuleGroup.account,
      permission: 'staff.view',
      color: Color(0xFF993C1D),
    ),
    AppModule(
      id: 'devices',
      title: 'Account Access',
      subtitle: 'Linked devices',
      icon: Icons.devices_rounded,
      route: '/devices',
      group: ModuleGroup.account,
      color: Color(0xFF0C447C),
    ),
    AppModule(
      id: 'wallet',
      title: 'Wallet',
      subtitle: 'Billing',
      icon: Icons.account_balance_wallet_rounded,
      route: '/wallet',
      group: ModuleGroup.account,
      permission: 'billing.view',
      color: Color(0xFF0F6E56),
    ),
    AppModule(
      id: 'plan_billing',
      title: 'Plan Billing',
      subtitle: 'Subscription & invoices',
      icon: Icons.receipt_long_rounded,
      route: '/account/plan-billing',
      group: ModuleGroup.account,
      permission: 'billing.view',
      color: Color(0xFF854F0B),
    ),
    AppModule(
      id: 'setup_guide',
      title: 'Setup Guides',
      subtitle: 'Get started',
      icon: Icons.checklist_rounded,
      route: '/setup-guide',
      group: ModuleGroup.account,
      color: Color(0xFF26215C),
    ),

    // ── Operations — everything still worth a shortcut that isn't part of the spec above ──
    AppModule(
      id: 'flow_builder',
      title: 'Flow Builder',
      subtitle: 'Automations',
      icon: Icons.account_tree_rounded,
      route: '/flow-builder',
      group: ModuleGroup.operations,
      permission: 'flows.view',
      color: Color(0xFF4338CA),
    ),
    AppModule(
      id: 'media_library',
      title: 'Media Library',
      subtitle: 'Files & folders',
      icon: Icons.perm_media_rounded,
      route: '/media-library',
      group: ModuleGroup.operations,
      permission: 'media.view',
      color: Color(0xFF12A594),
    ),
    AppModule(
      id: 'otp_service',
      title: 'OTP / API',
      subtitle: 'Developer service',
      icon: Icons.vpn_key_rounded,
      route: '/otp-service',
      group: ModuleGroup.operations,
      permission: 'otp.view',
      color: Color(0xFFE0475B),
    ),
    AppModule(
      id: 'export',
      title: 'Export',
      subtitle: 'Data export',
      icon: Icons.ios_share_rounded,
      route: '/export',
      group: ModuleGroup.operations,
      permission: 'export.view',
      color: Color(0xFF5C6570),
    ),
    AppModule(
      id: 'integrations',
      title: 'Integrations',
      subtitle: 'Sheets, Drive & more',
      icon: Icons.extension_rounded,
      route: '/integrations',
      group: ModuleGroup.operations,
      permission: 'integrations.view',
      color: Color(0xFF6D5EF0),
    ),
    AppModule(
      id: 'widget',
      title: 'Chat Widget',
      subtitle: 'Website chat',
      icon: Icons.chat_bubble_rounded,
      route: '/widget',
      group: ModuleGroup.operations,
      permission: 'widget.view',
      color: Color(0xFF6366F1),
    ),
    AppModule(
      id: 'analytics',
      title: 'Analytics',
      subtitle: 'Reports',
      icon: Icons.insights_rounded,
      route: '/reports',
      group: ModuleGroup.operations,
      permission: 'analytics.view',
      color: Color(0xFF7C3AED),
    ),
    AppModule(
      id: 'lead_summary',
      title: 'Lead Summary',
      subtitle: 'Dashboard',
      icon: Icons.pie_chart_rounded,
      route: '/lead-summary',
      group: ModuleGroup.operations,
      permission: 'leads.view',
      color: Color(0xFF0D9488),
    ),
    AppModule(
      id: 'settings',
      title: 'Settings',
      subtitle: 'Preferences',
      icon: Icons.settings_rounded,
      route: '/settings',
      group: ModuleGroup.operations,
      color: Color(0xFF5C6570),
    ),
    AppModule(
      id: 'superadmin',
      title: 'SuperAdmin',
      subtitle: 'Platform control',
      icon: Icons.shield_rounded,
      route: '/superadmin',
      group: ModuleGroup.operations,
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
    // Fall back to a path-only match in case a caller passes a route with a query string
    // attached — every catalogue entry is its own dedicated path now (no more `?tab=`
    // variants sharing one bare path), so this is mostly a defensive no-op today, kept for
    // robustness against `state.matchedLocation` growing a query string in the future.
    final path = route.split('?').first;
    for (final m in all) {
      if (m.route.split('?').first == path) return m;
    }
    return null;
  }
}
