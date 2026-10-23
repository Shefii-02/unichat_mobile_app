import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:unichat_mobile_app/core/nav/app_modules.dart';
import 'package:unichat_mobile_app/core/widgets/stub_page.dart';
import 'package:unichat_mobile_app/core/storage/local_storage.dart';
import 'package:unichat_mobile_app/features/app_lock/app_lock_page.dart';
import 'package:unichat_mobile_app/features/app_lock/app_lock_provider.dart';
import 'package:unichat_mobile_app/features/app_lock/app_lock_setup_prompt_page.dart';
import 'package:unichat_mobile_app/features/app_lock/change_mpin_page.dart';
import 'package:unichat_mobile_app/features/attendance/attendance_gate.dart';
import 'package:unichat_mobile_app/features/attendance/clock_in_required_page.dart';
import 'package:unichat_mobile_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:unichat_mobile_app/features/auth/presentation/pages/splash_page.dart';
import 'package:unichat_mobile_app/features/auth/presentation/pages/login_page.dart';
import 'package:unichat_mobile_app/features/auth/presentation/pages/device_login_page.dart';
import 'package:unichat_mobile_app/features/onboarding/onboarding_page.dart';
import 'package:unichat_mobile_app/features/home/home_page.dart';
import 'package:unichat_mobile_app/features/quick_actions/quick_actions_page.dart';
import 'package:unichat_mobile_app/features/hub/module_hub_page.dart';
import 'package:unichat_mobile_app/features/chats/presentation/pages/chats_page.dart';
import 'package:unichat_mobile_app/features/leads/presentation/pages/leads_page.dart';
import 'package:unichat_mobile_app/features/leads/presentation/pages/lead_detail_page.dart';
import 'package:unichat_mobile_app/features/contacts/presentation/pages/contacts_page.dart';
import 'package:unichat_mobile_app/features/contacts/presentation/pages/contact_detail_page.dart';
import 'package:unichat_mobile_app/features/books/presentation/pages/books_page.dart';
import 'package:unichat_mobile_app/features/campaigns/presentation/pages/campaigns_page.dart';
import 'package:unichat_mobile_app/features/notifications/presentation/pages/notifications_page.dart';
import 'package:unichat_mobile_app/features/settings/presentation/pages/settings_page.dart';
import 'package:unichat_mobile_app/features/more/more_page.dart';
import 'package:unichat_mobile_app/features/message_sender/message_sender_page.dart';
// WA Chat
import 'package:unichat_mobile_app/features/wa_chat/presentation/pages/wa_chat_dashboard_page.dart';
import 'package:unichat_mobile_app/features/wa_chat/presentation/pages/wa_sessions_page.dart';
import 'package:unichat_mobile_app/features/wa_chat/presentation/pages/automation_rules_page.dart';
import 'package:unichat_mobile_app/features/wa_chat/presentation/pages/inbox_analytics_page.dart';
import 'package:unichat_mobile_app/features/wa_chat/presentation/pages/audit_analytics_page.dart';
import 'package:unichat_mobile_app/features/wa_chat/presentation/pages/wa_data_export_page.dart';
import 'package:unichat_mobile_app/features/wa_chat/presentation/pages/wa_chat_templates_page.dart';
// WA Cloud
import 'package:unichat_mobile_app/features/wa_cloud/presentation/pages/cloud_phone_numbers_page.dart';
import 'package:unichat_mobile_app/features/wa_cloud/presentation/pages/wa_cloud_templates_page.dart';
import 'package:unichat_mobile_app/features/wa_cloud/presentation/pages/survey_forms_page.dart';
import 'package:unichat_mobile_app/features/wa_cloud/presentation/pages/wa_cloud_automations_page.dart';
import 'package:unichat_mobile_app/features/wa_cloud/presentation/pages/wa_cloud_inbox_analytics_page.dart';
import 'package:unichat_mobile_app/features/wa_cloud/presentation/pages/wa_cloud_inbox_page.dart';
import 'package:unichat_mobile_app/features/wa_cloud/presentation/pages/wa_cloud_settings_page.dart';
import 'package:unichat_mobile_app/features/wa_cloud/presentation/pages/wa_cloud_audit_log_page.dart';
import 'package:unichat_mobile_app/features/wa_cloud/presentation/pages/message_logs_page.dart';
import 'package:unichat_mobile_app/features/wa_cloud/presentation/pages/wa_cloud_api_service_page.dart';
// WA Agent
import 'package:unichat_mobile_app/features/wa_agent/presentation/pages/knowledge_base_page.dart';
import 'package:unichat_mobile_app/features/wa_agent/presentation/pages/pipelines_page.dart';
import 'package:unichat_mobile_app/features/wa_agent/presentation/pages/wa_agent_ai_agents_page.dart';
import 'package:unichat_mobile_app/features/wa_agent/presentation/pages/wa_agent_playbooks_page.dart';
import 'package:unichat_mobile_app/features/wa_agent/presentation/pages/lead_intelligence_page.dart';
import 'package:unichat_mobile_app/features/wa_agent/presentation/pages/wa_agent_logs_page.dart';
import 'package:unichat_mobile_app/features/wa_agent/presentation/pages/ai_config_page.dart';
import 'package:unichat_mobile_app/features/wa_agent/presentation/pages/wa_agent_ai_settings_page.dart';
import 'package:unichat_mobile_app/features/wa_agent/presentation/pages/wa_agent_catalog_page.dart';
// Meta Ads
import 'package:unichat_mobile_app/features/meta_ads/presentation/pages/meta_accounts_page.dart';
import 'package:unichat_mobile_app/features/meta_ads/presentation/pages/meta_campaigns_page.dart';
import 'package:unichat_mobile_app/features/meta_ads/presentation/pages/meta_audience_sets_page.dart';
import 'package:unichat_mobile_app/features/meta_ads/presentation/pages/meta_ads_insights_page.dart';
import 'package:unichat_mobile_app/features/meta_ads/presentation/pages/lead_ads_page.dart';
import 'package:unichat_mobile_app/features/meta_ads/presentation/pages/creative_studio_page.dart';
// Instagram
import 'package:unichat_mobile_app/features/instagram/presentation/pages/instagram_inbox_page.dart';
import 'package:unichat_mobile_app/features/instagram/presentation/pages/instagram_automations_page.dart';
import 'package:unichat_mobile_app/features/instagram/presentation/pages/instagram_comments_page.dart';
import 'package:unichat_mobile_app/features/instagram/presentation/pages/instagram_insights_page.dart';
// CRM & Sales
import 'package:unichat_mobile_app/features/crm_sales/presentation/pages/deals_page.dart';
import 'package:unichat_mobile_app/features/crm_sales/presentation/pages/crm_tasks_admin_page.dart';
import 'package:unichat_mobile_app/features/crm_sales/presentation/pages/calendar_page.dart';
import 'package:unichat_mobile_app/features/crm_sales/presentation/pages/labels_page.dart';
import 'package:unichat_mobile_app/features/crm_sales/presentation/pages/segments_page.dart';
import 'package:unichat_mobile_app/features/crm_sales/presentation/pages/blacklist_page.dart';
import 'package:unichat_mobile_app/features/crm_sales/presentation/pages/lead_categories_page.dart';
import 'package:unichat_mobile_app/features/crm_sales/presentation/pages/leads_by_staff_page.dart';
import 'package:unichat_mobile_app/features/crm_sales/presentation/pages/lead_logs_page.dart';
import 'package:unichat_mobile_app/features/crm_sales/presentation/pages/lead_report_page.dart';
import 'package:unichat_mobile_app/features/crm_sales/presentation/pages/assignment_queue_page.dart';
import 'package:unichat_mobile_app/features/crm_sales/presentation/pages/assignment_rules_page.dart';
// HR
import 'package:unichat_mobile_app/features/hr/presentation/pages/hr_attendance_all_page.dart';
import 'package:unichat_mobile_app/features/hr/presentation/pages/hr_leave_requests_page.dart';
import 'package:unichat_mobile_app/features/hr/presentation/pages/hr_payrolls_page.dart';
import 'package:unichat_mobile_app/features/hr/presentation/pages/hr_sales_page.dart';
import 'package:unichat_mobile_app/features/hr/presentation/pages/hr_incentives_page.dart';
import 'package:unichat_mobile_app/features/hr/presentation/pages/hr_staff_setup_page.dart';
import 'package:unichat_mobile_app/features/hr/presentation/pages/hr_break_types_page.dart';
import 'package:unichat_mobile_app/features/hr/presentation/pages/hr_leave_types_page.dart';
import 'package:unichat_mobile_app/features/hr/presentation/pages/hr_office_page.dart';
// Accounts
import 'package:unichat_mobile_app/features/accounts/presentation/pages/staff_team_page.dart';
import 'package:unichat_mobile_app/features/accounts/presentation/pages/roles_page.dart';
import 'package:unichat_mobile_app/features/accounts/presentation/pages/devices_page.dart';
import 'package:unichat_mobile_app/features/accounts/presentation/pages/wallet_page.dart';
import 'package:unichat_mobile_app/features/accounts/presentation/pages/plan_billing_page.dart';
import 'package:unichat_mobile_app/features/accounts/presentation/pages/setup_guide_page.dart';
// Operations
import 'package:unichat_mobile_app/features/operations/presentation/pages/flow_builder_page.dart';
import 'package:unichat_mobile_app/features/operations/presentation/pages/media_library_page.dart';
import 'package:unichat_mobile_app/features/operations/presentation/pages/otp_service_page.dart';
import 'package:unichat_mobile_app/features/operations/presentation/pages/export_page.dart';
import 'package:unichat_mobile_app/features/operations/presentation/pages/integrations_page.dart';
import 'package:unichat_mobile_app/features/operations/presentation/pages/widget_page.dart';
import 'package:unichat_mobile_app/features/operations/presentation/pages/analytics_page.dart';
import 'package:unichat_mobile_app/features/operations/presentation/pages/lead_summary_page.dart';
import 'package:unichat_mobile_app/features/operations/presentation/pages/superadmin_page.dart';
import 'package:unichat_mobile_app/features/target/target_page.dart';
import 'package:unichat_mobile_app/features/attendance/attendance_page.dart';
import 'package:unichat_mobile_app/features/modules/module_providers.dart';
import 'package:unichat_mobile_app/features/payroll/payroll_page.dart';
import 'package:unichat_mobile_app/features/profile/profile_page.dart';
import 'package:unichat_mobile_app/features/profile/edit_profile_page.dart';
import 'shell/main_shell.dart';

/// Bridges Riverpod auth + attendance-gate + app-lock state into a GoRouter-compatible
/// Listenable, so a redirect fires the instant any of them changes (e.g. once the
/// attendance fetch kicked off inside `redirect` resolves) — and observes app lifecycle to
/// re-lock (see AppLockNotifier.lock) whenever the app is backgrounded.
///
/// Deliberately has no client-side clock/timer logic for "did the day roll over" — the
/// device's date is only ever used as a cheap trigger to ask again, never as the answer
/// itself. The redirect's own attendance-gate check (below) compares `gate.fetchedForDate`
/// against today on every single navigation and re-fetches `/hr/attendance/me` whenever
/// they differ, so "is today already clocked in?" is always answered fresh by the server at
/// the moment it actually matters, not by a timer guessing when midnight happened.
class _AuthRouterNotifier extends ChangeNotifier with WidgetsBindingObserver {
  _AuthRouterNotifier(this._ref) {
    _ref.listen<AsyncValue<dynamic>>(
      authProvider,
      (_, __) => notifyListeners(),
    );
    _ref.listen<AttendanceGateState>(
      attendanceGateProvider,
      (_, __) => notifyListeners(),
    );
    _ref.listen<AppLockState>(appLockProvider, (_, __) => notifyListeners());
    WidgetsBinding.instance.addObserver(this);
  }

  final Ref _ref;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _ref.read(appLockProvider.notifier).lock();
    }
  }

  void disposeObserver() => WidgetsBinding.instance.removeObserver(this);
}

String _todayKey() {
  final now = DateTime.now();
  return '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
}

const _publicRoutes = {'/splash', '/onboarding', '/auth', '/login'};

/// Every user must clock in once per day — and end any open break — before
/// touching any other screen (including a deep link from a push
/// notification). This is the only route exempt from that gate.
const _gateExemptRoute = '/clock-in-required';

/// Route for the app-lock screen — PIN/biometric unlock, or (for an existing MPIN, right
/// after a fresh login) a reset-without-the-old-PIN flow, since identity was just proven
/// another way. First-time setup lives at [_appLockSetupRoute] instead. Exempt from both the
/// app-lock check itself (obviously) and the attendance gate, which must never be reachable
/// before the app is unlocked.
const _appLockRoute = '/app-lock';

/// The one-time, skippable "set up a PIN (and maybe biometric)" prompt shown right after a
/// fresh login on a device with no MPIN yet — exempt from the same checks as [_appLockRoute]
/// for the same reason.
const _appLockSetupRoute = '/app-lock-setup';

/// Routes that already have a bespoke mobile screen. Everything else in the
/// module catalogue falls back to [ModuleHubPage].
Widget _pageForModuleRoute(String route, GoRouterState state) {
  switch (route) {
    case '/campaigns':
      return const CampaignsPage();
    case '/accounts':
      return const BooksPage();
    case '/settings':
      return const SettingsPage();
    case '/reports':
      return const AnalyticsPage();
    // Meta Ads / Instagram / WA Agent / WA Cloud / Templates / Staff / HR used to be one
    // shared tabbed class each, picked with `?tab=N` — every former tab is now its own
    // independent page/route (see AppModules and the cases below); the bare group path keeps
    // only the tab-0 page (the one AppModules' un-suffixed entry already pointed at).
    case '/meta-ads':
      return const MetaAdsInsightsPage();
    case '/instagram':
      return const InstagramInboxPage();
    case '/ai-agent':
      return const WaAgentAiAgentsPage();
    case '/widget':
      return const WidgetPage();
    case '/knowledge-base':
      return const KnowledgeBasePage();
    case '/listings':
      return const WaAgentCatalogPage();
    case '/flow-builder':
      return const FlowBuilderPage();
    case '/wa-cloud':
      return const WaCloudInboxAnalyticsPage();
    case '/media-library':
      return const MediaLibraryPage();
    case '/staff':
      return const StaffTeamPage();
    case '/otp-service':
      return const OtpServicePage();
    case '/forms':
      return const SurveyFormsPage();
    case '/integrations':
      return const IntegrationsPage();
    case '/export':
      return const ExportPage();
    case '/wallet':
      return const WalletPage();
    case '/account/roles':
      return const RolesPage();
    case '/account/plan-billing':
      return const PlanBillingPage();
    case '/devices':
      return const DevicesPage();
    case '/setup-guide':
      return const SetupGuidePage();
    case '/superadmin':
      return const SuperAdminPage();
    case '/deals':
      return const DealsPage();
    case '/crm-tasks':
      return const CrmTasksAdminPage();
    case '/crm-followups':
      return const CrmTasksAdminPage(followups: true);
    case '/calendar':
      return const CalendarPage();
    case '/labels':
      return const LabelsPage();
    case '/segments':
      return const SegmentsPage();
    case '/blacklist':
      return const BlacklistPage();
    case '/lead-categories':
      return const LeadCategoriesPage();
    case '/leads-by-staff':
      return const LeadsByStaffPage();
    case '/lead-logs':
      return const LeadLogsPage();
    case '/lead-summary':
      return const LeadSummaryPage();
    case '/lead-report':
      return const LeadReportPage();
    case '/assignment-queue':
      return const AssignmentQueuePage();
    case '/assignment-rules':
      return const AssignmentRulesPage();

    case '/wa-chat/dashboard':
      return const WaChatDashboardPage();
    case '/wa-chat/sessions':
      return const WaSessionsPage();
    case '/wa-chat/message-sender':
      return const MessageSenderPage();
    case '/wa-cloud/phone-numbers':
      return const CloudPhoneNumbersPage();
    case '/wa-chat/automations':
      return const AutomationRulesPage();
    case '/wa-chat/analytics':
      return const InboxAnalyticsPage();
    case '/wa-chat/audit':
      return const AuditAnalyticsPage();
    case '/wa-chat/export':
      return const WaDataExportPage();
    case '/wa-cloud/settings':
      return const WaCloudSettingsPage();
    case '/wa-cloud/otp-service':
      return const WaCloudApiServicePage();
    case '/wa-cloud/audit-log':
      return const WaCloudAuditLogPage();
    case '/message-logs':
      return const MessageLogsPage();
    case '/wa-cloud/inbox':
      return const WaCloudInboxPage();
    case '/wa-agent/pipelines':
      return const PipelinesPage();
    case '/wa-agent/logs':
      return const WaAgentLogsPage();
    case '/wa-agent/lead-intelligence':
      return const LeadIntelligencePage();
    case '/wa-agent/ai-config':
      return const AiConfigPage();
    case '/wa-agent/settings':
      return const WaAgentAiSettingsPage();
    case '/meta-ads/lead-ads':
      return const LeadAdsPage();
    case '/meta-ads/creative-studio':
      return const CreativeStudioPage();
    case '/instagram/comments':
      return const InstagramCommentsPage();
    case '/instagram/insights':
      return const InstagramInsightsPage();
    case '/instagram/automations':
      return const InstagramAutomationsPage();
    case '/wa-agent/playbooks':
      return const WaAgentPlaybooksPage();
    case '/wa-chat/templates':
      return const WaChatTemplatesPage();
    case '/wa-cloud/templates':
      return const WaCloudTemplatesPage();
    case '/wa-cloud/automations':
      return const WaCloudAutomationsPage();
    case '/meta-ads/accounts':
      return const MetaAccountsPage();
    case '/meta-ads/campaigns':
      return const MetaCampaignsPage();
    case '/meta-ads/audience-sets':
      return const MetaAudienceSetsPage();

    // HR — each of the former HrAdminPage's 9 tabs is now its own page/route.
    case '/hr/attendance-all':
      return const HrAttendanceAllPage();
    case '/hr/leave-requests':
      return const HrLeaveRequestsPage();
    case '/hr/payrolls':
      return const HrPayrollsPage();
    case '/hr/sales':
      return const HrSalesPage();
    case '/hr/incentives':
      return const HrIncentivesPage();
    case '/hr/staff-setup':
      return const HrStaffSetupPage();
    case '/hr/break-types':
      return const HrBreakTypesPage();
    case '/hr/leave-types':
      return const HrLeaveTypesPage();
    case '/hr/office':
      return const HrOfficePage();
  }
  final module = AppModules.byRoute(route);
  if (module != null) return ModuleHubPage(module: module);
  return StubPage(title: route.replaceAll('/', ''), emoji: '🚧');
}

final routerProvider = Provider<GoRouter>((ref) {
  final notifier = _AuthRouterNotifier(ref);
  ref.onDispose(() {
    notifier.disposeObserver();
    notifier.dispose();
  });

  // Distinct module routes that are NOT served inside the bottom-nav shell. Several
  // catalogue entries deep-link into the same tabbed page with a different `?tab=N` query
  // (e.g. every HR sub-section shares '/hr') — only the bare path needs its own GoRoute, so
  // dedupe on that, not the full route-with-query string each AppModule carries.
  final moduleRoutes =
      AppModules.all
          .map((m) => m.route.split('?').first)
          .where(
            (r) =>
                !const {
                  '/wa-chat/chats',
                  '/leads',
                  '/contacts',
                  '/home',
                  '/target',
                  '/attendance',
                  '/payroll',
                  '/profile',
                  '/leads-by-staff',
                }.contains(r),
          )
          .toSet();

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: notifier,
    redirect: (context, state) {
      final auth = ref.read(authProvider);
      final loc = state.matchedLocation;

      if (loc == '/splash') return null; // splash routes itself
      if (auth.isLoading) return null;

      final loggedIn = auth.value != null;
      final isPublic = _publicRoutes.contains(loc);

      if (!loggedIn && !isPublic) return '/auth';
      if (loggedIn &&
          (loc == '/auth' || loc == '/login' || loc == '/onboarding')) {
        return '/home';
      }

      // Every module route was previously reachable by direct navigation regardless of role —
      // AppModule.visible (permission-checked) only ever decided which tiles rendered on the
      // Home/More screens, never what the router itself would allow. A user without the
      // relevant permission who knew/guessed the route (a saved deep link, a restored nav
      // state) could still open the page in full. Redirect away from any module route the
      // current user can't see a tile for, same as if they'd never been shown it.
      if (loggedIn && moduleRoutes.contains(loc)) {
        final module = AppModules.byRoute(loc);
        if (module != null && !module.visible) {
          return '/home';
        }
      }

      // App lock: block every screen behind the device PIN/biometric until unlocked — but
      // only for a device that actually has an MPIN set up (it's opt-in via Settings, never
      // forced). Checked before the attendance gate, since neither attendance data nor
      // anything else should be reachable pre-unlock on a device that IS locked.
      if (loggedIn && loc != _appLockRoute && loc != _appLockSetupRoute) {
        final lockState = ref.read(appLockProvider);
        // Fails safe before the first `refresh()` resolves (see AppLockNotifier.refresh) —
        // block until we actually know whether this device has an MPIN at all.
        if (!lockState.loaded) {
          return '$_appLockRoute?from=${Uri.encodeComponent(state.uri.toString())}';
        }
        if (lockState.hasMpin && lockState.locked) {
          return '$_appLockRoute?from=${Uri.encodeComponent(state.uri.toString())}';
        }
        // One-time, skippable "set up a PIN?" prompt for a device that's never had one and
        // has never seen this prompt before (see AppLockSetupPromptPage) — fires once ever,
        // right after whichever login got them here.
        if (!lockState.hasMpin &&
            !LocalStorage.getBool(LocalStorage.kAppLockSetupPromptSeen)) {
          return '$_appLockSetupRoute?from=${Uri.encodeComponent(state.uri.toString())}';
        }
      }

      // Attendance gate: block every screen until today's clock-in (and any open break) is
      // resolved. `loaded == false` means the fetch hasn't come back yet; `fetchedForDate`
      // not matching today means it came back for a day that has since passed (e.g. the app
      // sat open, or merely backgrounded, across midnight) — both cases re-fetch
      // `/hr/attendance/me` right here and route to the gate page, so "is today already
      // clocked in?" is always answered by the server at the moment it actually matters,
      // never assumed from a stale cache.
      if (loggedIn &&
          loc != _gateExemptRoute &&
          loc != _appLockRoute &&
          loc != _appLockSetupRoute) {
        final gate = ref.read(attendanceGateProvider);
        if (!gate.loaded || gate.fetchedForDate != _todayKey()) {
          ref.read(attendanceGateProvider.notifier).refresh();
          // The attendance card / dashboard aggregate are fetched once and cached until
          // invalidated — they don't know the calendar rolled over on their own, so nudge
          // them here too, at the same moment the gate itself notices.
          ref.invalidate(hrAttendanceMeProvider);
          ref.invalidate(dashboardMeProvider);
          ref.invalidate(attendanceCalendarProvider);
          return '$_gateExemptRoute?from=${Uri.encodeComponent(state.uri.toString())}';
        }
        if (gate.blocks) {
          return '$_gateExemptRoute?from=${Uri.encodeComponent(state.uri.toString())}';
        }
      }
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const SplashPage()),
      GoRoute(path: '/onboarding', builder: (_, __) => const OnboardingPage()),
      GoRoute(path: '/auth', builder: (_, __) => const DeviceLoginPage()),
      GoRoute(path: '/login', builder: (_, __) => const LoginPage()),

      // StatefulShellRoute (not a plain ShellRoute) — each tab keeps its own Navigator/state
      // in an IndexedStack behind ONE persistent Scaffold+BottomNavigationBar. A plain
      // ShellRoute rebuilds the whole shell (including the nav bar) on every navigation, and
      // `context.push('/leads')` from another tab would stack a second shell — with its own
      // second bottom nav — on top instead of switching tabs. Tab switches must use
      // `context.go(route)` (routes to the branch, see MainShell.goBranch), never `.push`.
      // Branch order must match MainShell: home, todo, chats, explore, attendance, payroll, profile,
      // then Leads/Target (no nav slot, still reachable via goToRoute).
      StatefulShellRoute.indexedStack(
        builder:
            (context, state, navigationShell) =>
                MainShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/home', builder: (_, __) => const HomePage()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/crm-tasks', builder: (_, __) => const CrmTasksAdminPage()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/wa-chat/chats', builder: (_, __) => const ChatsPage()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/more', builder: (_, __) => const MorePage()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/attendance',
                builder: (_, __) => const AttendancePage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/payroll',
                builder: (_, __) => const PayrollPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/profile',
                builder: (_, __) => const ProfilePage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/leads', builder: (_, __) => const LeadsPage()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/target', builder: (_, __) => const TargetPage()),
            ],
          ),
        ],
      ),

      // Lead detail is a full-screen sub-page, not part of the Leads tab's own
      // nested Navigator — kept as a sibling of the shell (like /chats/:id and
      // /contacts/:id below) so it doesn't inherit the bottom nav bar. Nesting
      // it under the /leads branch route used to do exactly that.
      GoRoute(
        path: '/lead-detail/:id',
        builder:
            (_, s) => LeadDetailPage(id: int.parse(s.pathParameters['id']!)),
      ),

      // Chats and Contacts lost their bottom-nav tab in the CRM staff-app nav
      // redesign — reached now via Home's quick actions / Profile menu instead,
      // pushed as flat routes (no persistent bottom nav while inside a chat).
      // ChatsPage is session-scoped (pick a WA session, see that session's live chats
      // straight from the gateway — see wa-chat/pages/Chats.tsx on the web) and pushes
      // straight to WaSessionChatRoomPage itself rather than a nested go_router route,
      // since a chat's identity (WA JID) only makes sense alongside its session/api key.
      GoRoute(
        path: '/contacts',
        builder: (_, __) => const ContactsPage(),
        routes: [
          GoRoute(
            path: ':id',
            builder:
                (_, s) =>
                    ContactDetailPage(id: int.parse(s.pathParameters['id']!)),
          ),
        ],
      ),
      GoRoute(
        path: '/leads-by-staff',
        builder: (_, __) => const LeadsByStaffPage(),
        routes: [
          GoRoute(
            path: ':id',
            builder:
                (_, s) => StaffLeadsPage(
                  staffId: int.parse(s.pathParameters['id']!),
                  staffName: s.uri.queryParameters['name'] ?? 'Staff',
                ),
          ),
        ],
      ),

      GoRoute(
        path: '/notifications',
        builder: (_, __) => const NotificationsPage(),
      ),
      GoRoute(
        path: '/quick-actions',
        builder: (_, __) => const QuickActionsPage(),
      ),
      GoRoute(
        path: _gateExemptRoute,
        builder: (_, __) => const ClockInRequiredPage(),
      ),
      GoRoute(
        path: _appLockRoute,
        builder:
            (_, s) => AppLockPage(
              redirectTo: s.uri.queryParameters['from'] ?? '/home',
            ),
      ),
      GoRoute(
        path: _appLockSetupRoute,
        builder:
            (_, s) => AppLockSetupPromptPage(
              redirectTo: s.uri.queryParameters['from'] ?? '/home',
            ),
      ),
      GoRoute(path: '/change-mpin', builder: (_, __) => const ChangeMpinPage()),
      GoRoute(
        path: '/edit-profile',
        builder: (_, __) => const EditProfilePage(),
      ),

      // One flat route per catalogue module.
      for (final route in moduleRoutes.where((r) => r != '/crm-tasks')) // '/crm-tasks' is a shell tab
        GoRoute(path: route, builder: (_, s) => _pageForModuleRoute(route, s)),
    ],
  );
});
