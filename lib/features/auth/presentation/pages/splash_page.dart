import 'package:unichat_mobile_app/core/widgets/teamzo_wordmark.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:unichat_mobile_app/core/storage/local_storage.dart';
import 'package:unichat_mobile_app/core/theme/app_theme.dart';
import 'package:unichat_mobile_app/core/version/update_checker.dart';
import 'package:unichat_mobile_app/features/auth/presentation/providers/auth_provider.dart';

class SplashPage extends ConsumerStatefulWidget {
  const SplashPage({super.key});
  @override
  ConsumerState<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends ConsumerState<SplashPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1100));
    _scale = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack);
    _fade = CurvedAnimation(parent: _ctrl, curve: const Interval(0.3, 1));
    _ctrl.forward();
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  Future<void> _boot() async {
    // Fire-and-forget: a store lookup, so don't let it delay app entry. Shows its "update
    // available" alert here if it resolves before we've navigated away; otherwise the
    // manual "Check for update" action in Settings covers it.
    unawaited(UpdateChecker.checkAndAlertIfNeeded(context));

    // Let the intro animation breathe.
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    if (!mounted) return;

    final auth = ref.read(authProvider);
    final loggedIn = auth.value != null;

    if (loggedIn) {
      // Confirm the linked device is still authorised before entering.
      final ok = await ref.read(authProvider.notifier).verifyDevice();

      if (!mounted) return;
      context.go(ok ? '/home' : '/auth');
      return;
    }

    final seenOnboarding =
        LocalStorage.getBool(LocalStorage.kOnboardingSeen, defaultValue: false);
    context.go(seenOnboarding ? '/auth' : '/onboarding');
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.accent,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ScaleTransition(
              scale: _scale,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: Image.asset('assets/logo/teamzo-icon-tight.png', width: 104, height: 104),
              ),
            ),
            const SizedBox(height: 22),
            FadeTransition(
              opacity: _fade,
              child: const Column(
                children: [
                  TeamzoWordmark(size: 40, color: Colors.white, accent: Color(0xFFD9DE4B)),
                  SizedBox(height: 6),
                  Text('One team. One app.',
                      style: TextStyle(color: Colors.white70, fontSize: 14)),
                ],
              ),
            ),
            const SizedBox(height: 46),
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                  color: Colors.white, strokeWidth: 2.4),
            ),
          ],
        ),
      ),
    );
  }
}
