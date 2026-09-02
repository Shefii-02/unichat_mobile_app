import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:overlay_support/overlay_support.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:unichat_mobile_app/core/router/app_router.dart';
import 'package:unichat_mobile_app/core/theme/app_theme.dart';

class UniChatApp extends ConsumerWidget {
  const UniChatApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return OverlaySupport.global(
      child: MaterialApp.router(
        title: 'UniChat',
        theme: lightTheme,
        darkTheme: darkTheme,
        themeMode: ThemeMode.light,
        routerConfig: router,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [
          Locale('en'),
          Locale('ml'),
          Locale('hi'),
        ],
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}
