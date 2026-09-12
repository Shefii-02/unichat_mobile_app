import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:overlay_support/overlay_support.dart';
import 'package:unichat_mobile_app/core/router/app_router.dart';
import 'package:unichat_mobile_app/core/services/heartbeat_service.dart';
import 'package:unichat_mobile_app/core/theme/app_theme.dart';
import 'package:unichat_mobile_app/core/theme/theme_provider.dart';

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
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final mode = ref.watch(themeModeProvider);

    return OverlaySupport.global(
      child: MaterialApp.router(
        title: 'Flowexa',
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: mode,
        routerConfig: router,
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
