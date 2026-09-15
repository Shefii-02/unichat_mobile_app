import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:unichat_mobile_app/core/nav/app_modules.dart';
import 'package:unichat_mobile_app/core/widgets/stub_page.dart';
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
import 'package:unichat_mobile_app/features/chats/presentation/pages/chat_detail_page.dart';
import 'package:unichat_mobile_app/features/leads/presentation/pages/leads_page.dart';
import 'package:unichat_mobile_app/features/leads/presentation/pages/lead_detail_page.dart';
import 'package:unichat_mobile_app/features/contacts/presentation/pages/contacts_page.dart';
import 'package:unichat_mobile_app/features/contacts/presentation/pages/contact_detail_page.dart';
import 'package:unichat_mobile_app/features/campaigns/presentation/pages/campaigns_page.dart';
import 'package:unichat_mobile_app/features/notifications/presentation/pages/notifications_page.dart';
import 'package:unichat_mobile_app/features/settings/presentation/pages/settings_page.dart';
import 'package:unichat_mobile_app/features/more/more_page.dart';
import 'package:unichat_mobile_app/features/message_sender/message_sender_page.dart';
import 'package:unichat_mobile_app/features/modules/account_pages.dart';
import 'package:unichat_mobile_app/features/modules/growth_pages.dart';
import 'package:unichat_mobile_app/features/modules/messaging_pages.dart';
import 'package:unichat_mobile_app/features/modules/ops_pages.dart';
import 'package:unichat_mobile_app/features/target/target_page.dart';
import 'package:unichat_mobile_app/features/attendance/attendance_page.dart';
import 'package:unichat_mobile_app/features/payroll/payroll_page.dart';
import 'package:unichat_mobile_app/features/profile/profile_page.dart';
import 'shell/main_shell.dart';

/// Bridges Riverpod auth + attendance-gate state into a GoRouter-compatible
/// Listenable, so a redirect fires the instant either changes (e.g. once the
/// attendance fetch kicked off inside `redirect` resolves).
class _AuthRouterNotifier extends ChangeNotifier {
  _AuthRouterNotifier(Ref ref) {
    ref.listen<AsyncValue<dynamic>>(authProvider, (_, __) => notifyListeners());
    ref.listen<AttendanceGateState>(
        attendanceGateProvider, (_, __) => notifyListeners());
  }
}

const _publicRoutes = {'/splash', '/onboarding', '/auth', '/login'};

/// Every user must clock in once per day — and end any open break — before
/// touching any other screen (including a deep link from a push
/// notification). This is the only route exempt from that gate.
const _gateExemptRoute = '/clock-in-required';

/// Routes that already have a bespoke mobile screen. Everything else in the
/// module catalogue falls back to [ModuleHubPage].
Widget _pageForModuleRoute(String route) {
  switch (route) {
    case '/message-sender':
      return const MessageSenderPage();
    case '/campaigns':
      return const CampaignsPage();
    case '/settings':
      return const SettingsPage();
    case '/reports':
      return const AnalyticsPage();
    case '/meta-ads':
      return const MetaAdsPage();
    case '/instagram':
      return const InstagramPage();
    case '/ai-agent':
      return const WaAgentPage();
    case '/widget':
      return const WidgetPage();
    case '/knowledge-base':
      return const KnowledgeBasePage();
    case '/listings':
      return const ListingsPage();
    case '/templates':
      return const TemplatesPage();
    case '/sessions':
      return const SessionsPage();
    case '/flow-builder':
      return const FlowBuilderPage();
    case '/wa-cloud':
      return const WaCloudPage();
    case '/media-library':
      return const MediaLibraryPage();
    case '/staff':
      return const StaffPage();
    case '/hr':
      return const HrPage();
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
    case '/devices':
      return const DevicesPage();
    case '/setup-guide':
      return const SetupGuidePage();
    case '/superadmin':
      return const SuperAdminPage();
  }
  final module = AppModules.byRoute(route);
  if (module != null) return ModuleHubPage(module: module);
  return StubPage(title: route.replaceAll('/', ''), emoji: '🚧');
}

final routerProvider = Provider<GoRouter>((ref) {
  final notifier = _AuthRouterNotifier(ref);
  ref.onDispose(notifier.dispose);

  // Distinct module routes that are NOT served inside the bottom-nav shell.
  final moduleRoutes = AppModules.all
      .map((m) => m.route)
      .where((r) => !const {
            '/chats', '/leads', '/contacts', '/home',
            '/target', '/attendance', '/payroll', '/profile',
          }.contains(r))
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
      if (loggedIn && (loc == '/auth' || loc == '/login' || loc == '/onboarding')) {
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

      // Attendance gate: block every screen until today's clock-in (and any
      // open break) is resolved. `loaded == false` means the fetch hasn't
      // come back yet — route to the gate page too rather than flash the
      // destination screen first; it kicks the fetch off itself.
      if (loggedIn && loc != _gateExemptRoute) {
        final gate = ref.read(attendanceGateProvider);
        if (!gate.loaded) {
          ref.read(attendanceGateProvider.notifier).refresh();
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

      ShellRoute(
        builder: (context, state, child) => MainShell(child: child),
        routes: [
          GoRoute(path: '/home', builder: (_, __) => const HomePage()),
          GoRoute(
            path: '/leads',
            builder: (_, __) => const LeadsPage(),
            routes: [
              GoRoute(
                path: ':id',
                builder: (_, s) =>
                    LeadDetailPage(id: int.parse(s.pathParameters['id']!)),
              ),
            ],
          ),
          GoRoute(path: '/target', builder: (_, __) => const TargetPage()),
          GoRoute(path: '/attendance', builder: (_, __) => const AttendancePage()),
          GoRoute(path: '/payroll', builder: (_, __) => const PayrollPage()),
          GoRoute(path: '/profile', builder: (_, __) => const ProfilePage()),
        ],
      ),

      // Chats and Contacts lost their bottom-nav tab in the CRM staff-app nav
      // redesign — reached now via Home's quick actions / Profile menu instead,
      // pushed as flat routes (no persistent bottom nav while inside a chat).
      GoRoute(
        path: '/chats',
        builder: (_, __) => const ChatsPage(),
        routes: [
          GoRoute(
            path: ':id',
            builder: (_, s) => ChatDetailPage(
              conversationId: int.parse(s.pathParameters['id']!),
            ),
          ),
        ],
      ),
      GoRoute(
        path: '/contacts',
        builder: (_, __) => const ContactsPage(),
        routes: [
          GoRoute(
            path: ':id',
            builder: (_, s) =>
                ContactDetailPage(id: int.parse(s.pathParameters['id']!)),
          ),
        ],
      ),
      GoRoute(path: '/more', builder: (_, __) => const MorePage()),

      GoRoute(path: '/notifications', builder: (_, __) => const NotificationsPage()),
      GoRoute(path: '/quick-actions', builder: (_, __) => const QuickActionsPage()),
      GoRoute(
          path: _gateExemptRoute, builder: (_, __) => const ClockInRequiredPage()),

      // One flat route per catalogue module.
      for (final route in moduleRoutes)
        GoRoute(path: route, builder: (_, __) => _pageForModuleRoute(route)),
    ],
  );
});
