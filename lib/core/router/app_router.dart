import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:unichat_mobile_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:unichat_mobile_app/features/auth/presentation/pages/splash_page.dart';
import 'package:unichat_mobile_app/features/auth/presentation/pages/login_page.dart';
import 'package:unichat_mobile_app/features/dashboard/presentation/pages/dashboard_page.dart';
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
import 'package:unichat_mobile_app/core/widgets/stub_page.dart';
import 'shell/main_shell.dart';

// Bridges Riverpod auth state into a GoRouter-compatible Listenable
class _AuthRouterNotifier extends ChangeNotifier {
  _AuthRouterNotifier(Ref ref) {
    ref.listen<AsyncValue<dynamic>>(authProvider, (_, __) => notifyListeners());
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final notifier = _AuthRouterNotifier(ref);
  ref.onDispose(notifier.dispose);

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: notifier,
    redirect: (context, state) {
      final authState = ref.read(authProvider);
      final isSplash = state.matchedLocation == '/splash';
      final isLogin  = state.matchedLocation == '/login';

      if (isSplash) return null;
      if (authState.isLoading) return null;

      final loggedIn = authState.value != null;
      if (!loggedIn && !isLogin) return '/login';
      if (loggedIn && isLogin)   return '/dashboard';
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const SplashPage()),
      GoRoute(path: '/login',  builder: (_, __) => const LoginPage()),
      ShellRoute(
        builder: (context, state, child) => MainShell(child: child),
        routes: [
          GoRoute(path: '/dashboard', builder: (_, __) => const DashboardPage()),
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
                builder: (_, s) => LeadDetailPage(id: int.parse(s.pathParameters['id']!)),
              ),
            ],
          ),
          GoRoute(
            path: '/contacts',
            builder: (_, __) => const ContactsPage(),
            routes: [
              GoRoute(
                path: ':id',
                builder: (_, s) => ContactDetailPage(id: int.parse(s.pathParameters['id']!)),
              ),
            ],
          ),
          GoRoute(path: '/more', builder: (_, __) => const MorePage()),
        ],
      ),
      GoRoute(path: '/notifications',  builder: (_, __) => const NotificationsPage()),
      GoRoute(path: '/campaigns',      builder: (_, __) => const CampaignsPage()),
      GoRoute(path: '/message-sender', builder: (_, __) => const MessageSenderPage()),
      GoRoute(path: '/settings',       builder: (_, __) => const SettingsPage()),
      GoRoute(path: '/reports',        builder: (_, __) => const StubPage(title: 'Reports',       emoji: '📊')),
      GoRoute(path: '/flow-builder',   builder: (_, __) => const StubPage(title: 'Flow Builder',  emoji: '🌊')),
      GoRoute(path: '/templates',      builder: (_, __) => const StubPage(title: 'Templates',     emoji: '🎯')),
      GoRoute(path: '/sessions',       builder: (_, __) => const StubPage(title: 'WA Sessions',   emoji: '📱')),
      GoRoute(path: '/otp-service',    builder: (_, __) => const StubPage(title: 'OTP Service',   emoji: '🔑')),
      GoRoute(path: '/ai-agent-test',  builder: (_, __) => const StubPage(title: 'AI Agent Test', emoji: '🤖')),
      GoRoute(path: '/staff',          builder: (_, __) => const StubPage(title: 'Staff',         emoji: '👥')),
      GoRoute(path: '/knowledge-base', builder: (_, __) => const StubPage(title: 'Knowledge Base',emoji: '📚')),
      GoRoute(path: '/export',         builder: (_, __) => const StubPage(title: 'Export',        emoji: '📤')),
      GoRoute(path: '/media-library',  builder: (_, __) => const StubPage(title: 'Media Library', emoji: '📁')),
    ],
  );
});
