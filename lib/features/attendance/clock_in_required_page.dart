import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:unichat_mobile_app/core/theme/mockup_palette.dart';
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
    final today = meAsync.maybeWhen(
      data: (d) => (d['today'] is Map) ? (d['today'] as Map).cast<String, dynamic>() : null,
      orElse: () => null,
    );
    final openBreak = meAsync.maybeWhen(
      data: (d) => (d['open_break'] is Map) ? (d['open_break'] as Map).cast<String, dynamic>() : null,
      orElse: () => null,
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
                  const SizedBox(height: 4),
                  Text(
                    _dateLabel(today),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: context.mutedColor, fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    onBreak
                        ? 'End your break to keep using the app.'
                        : "You need to clock in before you can use the app today.",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: context.mutedColor, height: 1.4),
                  ),
                  SizedBox(height: onBreak ? 20 : 0),
                  // Always present (never `if (...) ...` inserted/removed from this Column) —
                  // `openBreak` comes from `meAsync`, a *different* async provider from `gate`
                  // (already resolved by the time we reach this build, per the early-return
                  // above) that can still be loading when this page first mounts. Inserting a
                  // widget into the list the instant it resolves — at the same moment other
                  // providers on other screens are also settling — is exactly what previously
                  // tripped Flutter's semantics-flush assertion ("!semantics.parentDataDirty").
                  // Visibility keeps the child in the tree throughout; only its visibility (and
                  // the SizedBox height above) change with the data.
                  Visibility(
                    visible: onBreak && openBreak?['start_at'] != null,
                    maintainState: true,
                    maintainAnimation: true,
                    maintainSize: false,
                    child: _BreakInfoCard(startAt: (openBreak?['start_at'] as String?) ?? ''),
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
                      await ref.read(authProvider.notifier).logout(clearAppLock: true);
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

/// Prefers the server's own `work_date` for the row this gate is showing (so this never
/// disagrees with the day the actual clock-in/break data belongs to), only falling back to
/// the device's local date when there's no row yet at all (nothing clocked in today).
String _dateLabel(Map<String, dynamic>? today) {
  final raw = today?['work_date'];
  final parsed = raw != null ? DateTime.tryParse('$raw') : null;
  return DateFormat('EEEE, d MMMM').format(parsed ?? DateTime.now());
}

/// Break-in time plus a live-ticking "time on break so far" — reassures someone staring at
/// this blocking screen that the app knows exactly when their break started and is counting,
/// rather than just a static "you're on a break" with no numbers.
class _BreakInfoCard extends StatefulWidget {
  const _BreakInfoCard({required this.startAt});
  final String startAt;

  @override
  State<_BreakInfoCard> createState() => _BreakInfoCardState();
}

class _BreakInfoCardState extends State<_BreakInfoCard> {
  Timer? _ticker;
  Duration _elapsed = Duration.zero;
  DateTime? _start;

  @override
  void initState() {
    super.initState();
    _start = DateTime.tryParse(widget.startAt)?.toLocal();
    _tick();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    if (_start == null) return;
    final elapsed = DateTime.now().difference(_start!);
    if (mounted) setState(() => _elapsed = elapsed.isNegative ? Duration.zero : elapsed);
  }

  @override
  void didUpdateWidget(covariant _BreakInfoCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.startAt != widget.startAt) {
      _start = DateTime.tryParse(widget.startAt)?.toLocal();
      _tick();
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String _hms(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: M.amberBg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          Column(
            children: [
              Text('Break in', style: TextStyle(fontSize: 11, color: M.amberMuted, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(time12(widget.startAt),
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: M.amberTitle)),
            ],
          ),
          Container(width: 1, height: 32, color: M.amberMuted.withValues(alpha: 0.25)),
          Column(
            children: [
              Text('Total time', style: TextStyle(fontSize: 11, color: M.amberMuted, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(_hms(_elapsed),
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: M.amberTitle)),
            ],
          ),
        ],
      ),
    );
  }
}
