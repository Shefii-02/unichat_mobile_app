import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:unichat_mobile_app/core/nav/app_modules.dart';
import 'package:unichat_mobile_app/core/widgets/stub_page.dart';
import 'package:unichat_mobile_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:unichat_mobile_app/features/auth/presentation/pages/splash_page.dart';
import 'package:unichat_mobile_app/features/auth/presentation/pages/login_page.dart';
import 'package:unichat_mobile_app/features/auth/presentation/pages/device_login_page.dart';
import 'package:unichat_mobile_app/features/onboarding/onboarding_page.dart';
import 'package:unichat_mobile_app/features/home/home_page.dart';
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
import 'shell/main_shell.dart';

/// Bridges Riverpod auth state into a GoRouter-compatible Listenable.
class _AuthRouterNotifier extends ChangeNotifier {
  _AuthRouterNotifier(Ref ref) {
    ref.listen<AsyncValue<dynamic>>(authProvider, (_, __) => notifyListeners());
  }
}

const _publicRoutes = {'/splash', '/onboarding', '/auth', '/login'};

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
      .where((r) => !const {'/chats', '/leads', '/contacts', '/home'}.contains(r))
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
        ],
      ),

      GoRoute(path: '/notifications', builder: (_, __) => const NotificationsPage()),

      // One flat route per catalogue module.
      for (final route in moduleRoutes)
        GoRoute(path: route, builder: (_, __) => _pageForModuleRoute(route)),
    ],
  );
});
