import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:unichat_mobile_app/core/network/api.dart';

/// Simple read-only endpoint providers shared by the module screens. Each is a
/// `FutureProvider`; call `ref.invalidate(x)` to refresh.

// ── Analytics ───────────────────────────────────────────────────────────
final analyticsOverviewProvider = FutureProvider((ref) => Api.one('/analytics/overview'));
final analyticsLeadsProvider =
    FutureProvider((ref) => Api.one('/analytics/leads'));
final analyticsWalletProvider =
    FutureProvider((ref) => Api.one('/analytics/wallet'));

// ── Meta Ads ────────────────────────────────────────────────────────────
final metaAccountsProvider =
    FutureProvider((ref) => Api.list('/meta-ads/accounts'));
final metaCampaignsProvider =
    FutureProvider((ref) => Api.list('/meta-ads/campaigns'));
final metaInsightsOverviewProvider = FutureProvider((ref) => Api.one('/meta-ads/insights/overview'));
final metaAudienceSetsProvider =
    FutureProvider((ref) => Api.list('/meta-ads/audience-sets'));
final metaLeadFormsProvider =
    FutureProvider((ref) => Api.list('/meta-ads/lead-forms'));

// ── Instagram ───────────────────────────────────────────────────────────
final igAccountsProvider =
    FutureProvider((ref) => Api.list('/instagram/accounts'));
final igConversationsProvider =
    FutureProvider((ref) => Api.list('/instagram/conversations'));
final igAutomationsProvider =
    FutureProvider((ref) => Api.list('/instagram/automations'));

// ── Templates ───────────────────────────────────────────────────────────
final waCloudTemplatesProvider =
    FutureProvider((ref) => Api.list('/templates'));
final waChatTemplatesProvider =
    FutureProvider((ref) => Api.list('/wa-chat-templates'));

// ── Phone numbers / WA sessions ─────────────────────────────────────────
final phoneNumbersProvider =
    FutureProvider((ref) => Api.list('/phone-numbers'));
final wahaSessionsProvider =
    FutureProvider((ref) => Api.list('/waha/sessions'));

// ── HR ──────────────────────────────────────────────────────────────────
final hrAttendanceMeProvider =
    FutureProvider((ref) => Api.one('/hr/attendance/me'));
// Home-screen aggregate — attendance + sales target + streak + rank +
// leads/pipeline/follow-ups/tasks in one call. See DashboardController@me.
final dashboardMeProvider =
    FutureProvider((ref) => Api.one('/hr/dashboard/me'));
// Per-day status for a month (present/absent/on_leave/half_day/weekly_off/upcoming) +
// month tile counts — powers the Attendance screen's calendar strip. Family param is the
// month ("YYYY-MM"); null means "current month" (server default).
final attendanceCalendarProvider =
    FutureProvider.family<Map<String, dynamic>, String?>(
  (ref, month) => Api.one('/hr/attendance/me/calendar', query: month != null ? {'month': month} : null),
);
// Per-day clock in/out + breaks + leave for a month — powers the Attendance screen's
// "Recent activity" list.
final attendanceHistoryProvider =
    FutureProvider.family<Map<String, dynamic>, String?>(
  (ref, month) => Api.one('/hr/attendance/me/history', query: month != null ? {'month': month} : null),
);

// ── Sales / Target ──────────────────────────────────────────────────────
// Target screen aggregate — own progress, weekly breakdown, days left, leaderboard. Family
// param is the month ("YYYY-MM"); null means "current month".
final salesMeProvider = FutureProvider.family<Map<String, dynamic>, String?>(
  (ref, month) => Api.one('/hr/sales/me', query: month != null ? {'month': month} : null),
);

// ── Payroll (self-service) ───────────────────────────────────────────────
// The caller's own payslip for a period ("YYYY-MM", null = latest released). Null result
// means no released payslip exists yet for that period.
final payrollMeProvider =
    FutureProvider.family<Map<String, dynamic>?, String?>((ref, period) async {
  final res = await Api.one('/hr/payroll/me', query: period != null ? {'period': period} : null);
  final data = res['data'];
  return (data is Map) ? data.cast<String, dynamic>() : null;
});
final payrollHistoryProvider =
    FutureProvider((ref) => Api.list('/hr/payroll/me/history'));

// ── Notification preferences (self-service) ───────────────────────────────
final notificationPreferencesProvider =
    FutureProvider((ref) => Api.one('/notification-preferences/me'));
final hrLeaveProvider =
    FutureProvider((ref) => Api.list('/hr/leave'));
// Today's team attendance — only resolves for users with hr.manage /
// hr.attendance.view_all / staff.view (server-enforced); callers should gate
// the section on the equivalent client-side permission before watching this.
final hrTeamAttendanceTodayProvider =
    FutureProvider((ref) => Api.list('/hr/attendance'));

// ── CRM tasks ───────────────────────────────────────────────────────────
final crmMyTasksProvider =
    FutureProvider((ref) => Api.list('/crm/tasks', query: {'mine': true}));

// ── Staff ───────────────────────────────────────────────────────────────
final staffListProvider =
    FutureProvider((ref) => Api.list('/staff'));
final rolesListProvider =
    FutureProvider((ref) => Api.list('/roles'));

// ── Wallet ──────────────────────────────────────────────────────────────
final walletProvider = FutureProvider((ref) => Api.one('/wallet'));
final walletTxProvider =
    FutureProvider((ref) => Api.list('/wallet/transactions'));
final currentPlanProvider =
    FutureProvider((ref) => Api.one('/plans/current'));

// ── Devices ─────────────────────────────────────────────────────────────
// Full object (not Api.list) so the page can also show "X of Y device slots
// used" from `max`/`active`, not just the device rows.
final devicesProvider = FutureProvider((ref) => Api.one('/devices'));

// ── Knowledge base ──────────────────────────────────────────────────────
final knowledgeBaseProvider = FutureProvider((ref) => Api.list('/wa-agent/knowledge-base'));

// ── Listings ────────────────────────────────────────────────────────────
final listingsProvider =
    FutureProvider((ref) => Api.list('/listings'));

// ── WA Cloud ────────────────────────────────────────────────────────────
final waCloudInboxAnalyticsProvider = FutureProvider((ref) => Api.one('/wa-cloud/inbox-analytics'));
final waCloudAutomationsProvider = FutureProvider((ref) => Api.list('/wa-cloud/automations'));

// ── Flow builder ────────────────────────────────────────────────────────
final flowBuildersProvider =
    FutureProvider((ref) => Api.list('/flow-builders'));

// ── Media library ───────────────────────────────────────────────────────
final mediaLibraryProvider =
    FutureProvider((ref) => Api.list('/media-library'));
final mediaFoldersProvider =
    FutureProvider((ref) => Api.list('/media-library/folders'));

// ── OTP service ─────────────────────────────────────────────────────────
final otpServiceProvider =
    FutureProvider((ref) => Api.one('/otp-service'));
final otpServiceLogsProvider =
    FutureProvider((ref) => Api.list('/otp-service/logs'));

// ── Data export ─────────────────────────────────────────────────────────
final exportJobsProvider =
    FutureProvider((ref) => Api.list('/wa-export'));

// ── Survey forms ────────────────────────────────────────────────────────
final surveyFormsProvider =
    FutureProvider((ref) => Api.list('/survey-forms'));

// ── Integrations (Google) ───────────────────────────────────────────────
final googleStatusProvider =
    FutureProvider((ref) => Api.one('/google/status'));
final companyApiKeysProvider =
    FutureProvider((ref) => Api.list('/settings/api-keys'));

// ── WA Agent ────────────────────────────────────────────────────────────
final waAgentStatsProvider =
    FutureProvider((ref) => Api.one('/wa-agent/stats'));
final waAgentSessionsProvider =
    FutureProvider((ref) => Api.list('/wa-agent/sessions'));
final waAgentPlaybookProvider =
    FutureProvider((ref) => Api.list('/wa-agent/playbook'));
final waAgentAutomationsProvider = FutureProvider((ref) => Api.list('/wa-agent/automations'));

// ── Widgets (website chat) ──────────────────────────────────────────────
final chatWidgetsProvider =
    FutureProvider((ref) => Api.list('/widgets'));

// ── SuperAdmin ──────────────────────────────────────────────────────────
final superAdminDashboardProvider =
    FutureProvider((ref) => Api.one('/superadmin/dashboard'));
final superAdminCompaniesProvider =
    FutureProvider((ref) => Api.list('/superadmin/companies'));

// ── Setup guide (derived from several status endpoints) ──────────────────
final setupStatusProvider = FutureProvider((ref) async {
  Future<Map<String, dynamic>?> tryGet(String p) async {
    try {
      return await Api.one(p);
    } catch (_) {
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> tryList(String p) async {
    try {
      return await Api.list(p);
    } catch (_) {
      return const [];
    }
  }

  final sessions = await tryList('/waha/sessions');
  final phones = await tryList('/phone-numbers');
  final templates = await tryList('/templates');
  final kb = await tryList('/wa-agent/knowledge-base');
  final playbook = await tryList('/wa-agent/playbook');
  final google = await tryGet('/google/status');
  final listings = await tryList('/listings');

  return {
    'session_connected':
        sessions.any((s) => '${s['status']}'.toLowerCase().contains('work') ||
            '${s['status']}'.toLowerCase() == 'connected'),
    'phone_added': phones.isNotEmpty,
    'templates_created': templates.isNotEmpty,
    'kb_added': kb.isNotEmpty,
    'agent_configured': playbook.isNotEmpty,
    'google_connected': google?['connected'] == true,
    'listings_added': listings.isNotEmpty,
  };
});
