import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:unichat_mobile_app/core/theme/mockup_palette.dart';
import 'package:unichat_mobile_app/features/attendance/widgets/attendance_status_card.dart';
import 'package:unichat_mobile_app/features/modules/_shared.dart';
import 'package:unichat_mobile_app/features/modules/module_providers.dart';

const _weekdayLetters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

/// Full attendance screen: today's clock-in/out card, this month's present/absent/late/leave
/// tile counts, a current-week calendar strip, and a recent-activity list — all from
/// `GET /hr/attendance/me/calendar` + `/me/history` (see AttendanceController@myCalendar).
class AttendancePage extends ConsumerWidget {
  const AttendancePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final monthLabel = _monthName(DateTime.now().month);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(hrAttendanceMeProvider);
            ref.invalidate(attendanceCalendarProvider);
            ref.invalidate(attendanceHistoryProvider);
          },
          child: ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              Container(
                width: double.infinity,
                color: M.heroBg,
                padding: const EdgeInsets.fromLTRB(20, 10, 18, 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Attendance',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Colors.white)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                      child: Text(monthLabel, style: const TextStyle(fontSize: 12, color: Colors.white)),
                    ),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: AttendanceStatusCard(),
              ),
              const _MonthCounts(),
              const _CalendarStrip(),
              const _RecentActivity(),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  static String _monthName(int m) => const [
        '', 'January', 'February', 'March', 'April', 'May', 'June',
        'July', 'August', 'September', 'October', 'November', 'December',
      ][m];
}

class _MonthCounts extends ConsumerWidget {
  const _MonthCounts();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(attendanceCalendarProvider(null));
    return async.maybeWhen(
      orElse: () => const SizedBox(height: 0),
      data: (d) {
        final counts = (d['counts'] is Map) ? (d['counts'] as Map) : const {};
        final tiles = <(String, Object?, Tint)>[
          ('Present', counts['present'], tintGreen),
          ('Absent', counts['absent'], tintRed),
          ('Late', counts['late'], tintAmber),
          ('Leave', counts['leave'], tintBlue),
        ];
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Row(
            children: tiles
                .map((t) => Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(right: t == tiles.last ? 0 : 8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
                          decoration: BoxDecoration(color: t.$3.$1, borderRadius: BorderRadius.circular(12)),
                          child: Column(
                            children: [
                              Text('${t.$2 ?? 0}',
                                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: t.$3.$2)),
                              Text(t.$1, style: TextStyle(fontSize: 9, color: t.$3.$3)),
                            ],
                          ),
                        ),
                      ),
                    ))
                .toList(),
          ),
        );
      },
    );
  }
}

class _CalendarStrip extends ConsumerWidget {
  const _CalendarStrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(attendanceCalendarProvider(null));
    return async.maybeWhen(
      orElse: () => const SizedBox(height: 0),
      data: (d) {
        final days = (d['days'] is List) ? (d['days'] as List).whereType<Map>().toList() : const <Map>[];
        if (days.isEmpty) return const SizedBox(height: 0);

        final byDate = {for (final r in days) r['date']: r};
        final now = DateTime.now();
        final weekStart = now.subtract(Duration(days: now.weekday - 1));
        final today = DateTime(now.year, now.month, now.day);

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
          child: Row(
            children: List.generate(7, (i) {
              final date = weekStart.add(Duration(days: i));
              final key = _iso(date);
              final row = byDate[key];
              final status = row?['status'] as String?;
              final lateThatDay = row?['late'] == true;
              final isToday = DateTime(date.year, date.month, date.day) == today;
              final (bg, fg) = isToday
                  ? (M.heroAvatarBg, Colors.white)
                  : switch (status) {
                      'present' => (M.attBtnBorder, M.attTitle),
                      'half_day' => (M.attBtnBorder, M.attTitle),
                      'on_leave' => (tintBlue.$1, tintBlue.$2),
                      'absent' => (const Color(0xFFF09595), M.redTitle),
                      _ => (const Color(0xFFF4F3FB), context.mutedColor),
                    };

              return Expanded(
                child: Column(
                  children: [
                    Text(_weekdayLetters[i],
                        style: TextStyle(
                            fontSize: 10,
                            color: isToday ? M.heroAvatarBg : context.mutedColor,
                            fontWeight: isToday ? FontWeight.w600 : FontWeight.normal)),
                    const SizedBox(height: 4),
                    Container(
                      width: 28,
                      height: 28,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                          color: lateThatDay ? M.gold : bg, borderRadius: BorderRadius.circular(8)),
                      child: Text('${date.day}',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: lateThatDay ? M.goldTitle : fg)),
                    ),
                  ],
                ),
              );
            }),
          ),
        );
      },
    );
  }

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

class _RecentActivity extends ConsumerWidget {
  const _RecentActivity();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(attendanceHistoryProvider(null));
    return async.maybeWhen(
      orElse: () => const SizedBox(height: 0),
      data: (d) {
        final rows = (d['data'] is List) ? (d['data'] as List).whereType<Map>().toList() : const <Map>[];
        final withClockIn = rows.where((r) => r['clock_in_at'] != null).take(6).toList();
        if (withClockIn.isEmpty) return const SizedBox(height: 0);

        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionHeader('Recent activity'),
              ...withClockIn.map((r) {
                final workDate = DateTime.tryParse('${r['work_date']}');
                final today = DateTime.now();
                final isToday = workDate != null &&
                    workDate.year == today.year && workDate.month == today.month && workDate.day == today.day;
                final dateLabel = workDate == null
                    ? '—'
                    : isToday
                        ? 'Today, ${_shortMonth(workDate.month)} ${workDate.day}'
                        : '${_weekdayName(workDate.weekday)}, ${_shortMonth(workDate.month)} ${workDate.day}';
                final range = '${time12(r['clock_in_at'])} – ${r['clock_out_at'] != null ? time12(r['clock_out_at']) : 'now'}';
                final late = (r['late_minutes'] ?? 0) is num && (r['late_minutes'] as num) > 0;

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Container(
                        width: 8, height: 8,
                        decoration: BoxDecoration(
                            color: late ? M.priorityMed : M.attDot, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(dateLabel, style: const TextStyle(fontSize: 12)),
                      ),
                      Text(range, style: TextStyle(fontSize: 11, color: context.mutedColor)),
                    ],
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }

  static String _weekdayName(int wd) =>
      const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][wd - 1];
  static String _shortMonth(int m) => const [
        '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ][m];
}
