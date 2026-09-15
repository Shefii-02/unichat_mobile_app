import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:unichat_mobile_app/features/attendance/attendance_actions.dart';
import 'package:unichat_mobile_app/features/attendance/attendance_gate.dart';
import 'package:unichat_mobile_app/features/attendance/leave_request.dart';
import 'package:unichat_mobile_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:unichat_mobile_app/features/modules/_shared.dart';
import 'package:unichat_mobile_app/features/modules/module_providers.dart';

/// Full-screen gate shown instead of any tab/page whenever the signed-in user
/// hasn't clocked in yet today, or is on an open break. No bottom nav, no
/// header tabs, and — wrapped in [PopScope] — no system-back / swipe-back
/// escape hatch back to whatever screen sits underneath it on the stack;
/// clocking in / ending the break (or signing out) are the only ways out.
class ClockInRequiredPage extends ConsumerWidget {
  const ClockInRequiredPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gate = ref.watch(attendanceGateProvider);
    final meAsync = ref.watch(hrAttendanceMeProvider);
    final settings = meAsync.maybeWhen(
      data: (d) => (d['settings'] is Map)
          ? (d['settings'] as Map).cast<String, dynamic>()
          : <String, dynamic>{},
      orElse: () => <String, dynamic>{},
    );
    final from = GoRouterState.of(context).uri.queryParameters['from'];

    if (!gate.loaded) {
      return const PopScope(
        canPop: false,
        child: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }

    if (!gate.blocks) {
      // Resolved elsewhere (e.g. another tab already actioned it) — leave.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          context.go((from != null && from.isNotEmpty) ? from : '/home');
        }
      });
      return const PopScope(
        canPop: false,
        child: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }

    final onBreak = gate.onBreak;
    final theme = Theme.of(context);

    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      onBreak
                          ? Icons.free_breakfast_rounded
                          : Icons.work_history_rounded,
                      size: 40,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 22),
                  Text(
                    onBreak ? "You're on a break" : 'Start your day',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    onBreak
                        ? 'End your break to keep using the app.'
                        : "You need to clock in before you can use the app today.",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: context.mutedColor, height: 1.4),
                  ),
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => _act(context, ref,
                          onBreak: onBreak, from: from, settings: settings),
                      icon: Icon(
                        onBreak
                            ? Icons.play_arrow_rounded
                            : Icons.login_rounded,
                      ),
                      label: Text(onBreak ? 'End break' : 'Clock in'),
                    ),
                  ),
                  if (!onBreak) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => requestLeave(context, ref),
                        icon: const Icon(Icons.beach_access_rounded),
                        label: const Text('Request leave instead'),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () async {
                      if (!await confirm(
                        context,
                        title: 'Sign out?',
                        message: 'You will need to sign back in.',
                        destructive: true,
                        confirmLabel: 'Sign out',
                      )) {
                        return;
                      }
                      await ref.read(authProvider.notifier).logout();
                    },
                    child: const Text('Sign out instead'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _act(
    BuildContext context,
    WidgetRef ref, {
    required bool onBreak,
    required Map<String, dynamic> settings,
    String? from,
  }) async {
    final ok = await attendanceAction(
      context,
      action: onBreak ? 'break_end' : 'clock_in',
      settings: settings,
    );
    ref.invalidate(hrAttendanceMeProvider);
    // Refresh regardless of `ok` — a failure like "Already clocked in today"
    // means our cached gate state was stale, not that the user is still
    // blocked, so re-check rather than leaving them stuck on this page.
    await ref.read(attendanceGateProvider.notifier).refresh();
    if (!context.mounted) return;
    if (ok || !ref.read(attendanceGateProvider).blocks) {
      context.go((from != null && from.isNotEmpty) ? from : '/home');
    }
  }
}
