import 'package:flutter/material.dart';
import 'package:unichat_mobile_app/services/push_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:overlay_support/overlay_support.dart';
import 'package:unichat_mobile_app/core/network/dio_client.dart';
import 'package:unichat_mobile_app/core/router/app_router.dart';
import 'package:unichat_mobile_app/core/services/heartbeat_service.dart';
import 'package:unichat_mobile_app/core/theme/app_theme.dart';
import 'package:unichat_mobile_app/core/theme/theme_provider.dart';
import 'package:unichat_mobile_app/features/auth/presentation/providers/auth_provider.dart';

class FlowexaApp extends ConsumerStatefulWidget {
  const FlowexaApp({super.key});

  @override
  ConsumerState<FlowexaApp> createState() => _FlowexaAppState();
}

class _FlowexaAppState extends ConsumerState<FlowexaApp> {
  @override
  void initState() {
    super.initState();
    ref.read(heartbeatServiceProvider).start();
    // See DioClient.onAuthFailure's doc comment — this is what actually gets the user
    // bounced to device re-login (QR/PIN) the moment a request proves their token is dead,
    // instead of them being stuck on a broken screen until they restart the app.
    DioClient.onAuthFailure =
        () => ref.read(authProvider.notifier).forceSignOut();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authProvider, (prev, next) {
      final was = prev?.value != null;
      final now = next.value != null;
      if (now && !was) PushService.instance.register();
    });
    final router = ref.watch(routerProvider);
    final mode = ref.watch(themeModeProvider);

    return OverlaySupport.global(
      child: MaterialApp.router(
        title: 'Teamzo',
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: mode,
        routerConfig: router,
        scrollBehavior: const _AlwaysScrollBehavior(),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en'), Locale('ml'), Locale('hi')],
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}

/// Makes every scrollable overscroll-able even when its content is shorter than the
/// screen, so pull-to-refresh works on short lists too.
class _AlwaysScrollBehavior extends MaterialScrollBehavior {
  const _AlwaysScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const AlwaysScrollableScrollPhysics().applyTo(
        super.getScrollPhysics(context),
      );
}
