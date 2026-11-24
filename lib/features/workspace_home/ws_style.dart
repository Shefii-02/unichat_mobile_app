import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:unichat_mobile_app/core/permissions/permission_guard.dart';
import 'package:unichat_mobile_app/core/theme/mockup_palette.dart';
import 'package:unichat_mobile_app/features/attendance/widgets/attendance_status_card.dart';
import 'package:unichat_mobile_app/features/modules/_shared.dart';

/// Building blocks for the workspace Home bodies (Sales / Administrators / HR / Marketing / Accounts), in the SAME look as the Company Admin Home:
/// the purple hero summary, pastel stat tiles, plain section headers and soft rounded list cards.

/// One call per workspace (GET /home/{workspace}) — everything its Home shows; empty sections come back empty, never as an error.
final wsHomeProvider = FutureProvider.family<Map<String, dynamic>, String>((ref, key) => Api.one('/home/$key'));
final wsAccountsProvider = FutureProvider<Map<String, dynamic>>((ref) => Api.one('/accounts/dashboard'));
final wsReceivableProvider = FutureProvider<Map<String, dynamic>>((ref) => Api.one('/accounts/payments/receivable', query: {'status': 'open'}));

num? n(Object? v) => v is num ? v : num.tryParse('${v ?? ''}');
Map<String, dynamic>? asMap(Object? v) => v is Map ? v.cast<String, dynamic>() : null;
List<Map<String, dynamic>> asRows(Object? v) => v is List ? v.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList() : const [];
T? dataOf<T>(AsyncValue<T> v) => v.maybeWhen(data: (d) => d, orElse: () => null);

String fmtNum(Object? v) {
  final x = n(v);
  if (x == null) return '—';
  final s = x.abs() >= 100 ? x.round().toString() : x.toString();
  return s.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');
}

String fmtMoney(Object? v) {
  final x = n(v);
  if (x == null) return '—';
  final a = x.abs();
  final sign = x < 0 ? '-' : '';
  if (a >= 10000000) return '$sign₹${(a / 10000000).toStringAsFixed(1)}Cr';
  if (a >= 100000) return '$sign₹${(a / 100000).toStringAsFixed(1)}L';
  if (a >= 1000) return '$sign₹${(a / 1000).toStringAsFixed(1)}K';
  return '$sign₹${a.round()}';
}

/// "5m / 2h / 3d" since [iso], or "" when it can't be read.
String wsAgo(String iso) {
  final d = DateTime.tryParse(iso)?.toLocal();
  if (d == null) return '';
  final m = DateTime.now().difference(d).inMinutes;
  if (m < 1) return 'now';
  if (m < 60) return '${m}m';
  if (m < 1440) return '${m ~/ 60}h';
  return '${m ~/ 1440}d';
}

String wsClock(String iso) {
  final d = DateTime.tryParse(iso)?.toLocal();
  return d == null ? 'Open' : '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

/// The clock-in / attendance card, exactly as on the Company Admin Home — right under each workspace's summary (when the plan includes HR).
class WsAttendance extends StatelessWidget {
  const WsAttendance({super.key});
  @override
  Widget build(BuildContext context) => PermissionGuard.entitled('hr') ? const Padding(padding: EdgeInsets.fromLTRB(16, 16, 16, 0), child: AttendanceStatusCard()) : const SizedBox.shrink();
}

/// True when the signed-in user holds ANY of [perms] (owners / superadmins always do) — or no permission is required.
bool wsAllowed(List<String>? perms) => perms == null || perms.isEmpty || perms.any(PermissionGuard.can);

/// Permission(s) behind each stat tile (by its label), so every tile shows only for someone whose role / sections / extras allow it.
const _tilePerms = <String, List<String>>{
  'Leads': ['leads.view'], 'My leads': ['leads.view'], 'New leads': ['leads.view'], 'Contacts': ['contacts.view'], 'Follow-ups': ['contacts.view'],
  'Chats': ['wa_chat.chats.view', 'inbox.view'],
  'Leave': ['hr.leave.approve', 'hr.manage'], 'Payroll': ['hr.manage'], 'Directory': ['staff.view'],
  'Staff': ['staff.view'], 'Roles': ['roles.view'], 'Devices': ['devices.view'], 'Integrations': ['integrations.view'],
  'Campaigns': ['campaigns.view', 'meta_ads.view'], 'Templates': ['templates.view'], 'Flows': ['flow_builder.view', 'instagram.view'], 'Social & ads': ['instagram.view', 'meta_ads.view'],
  'Books': ['accounts.read'], 'Receivable': ['accounts.read'], 'Payable': ['accounts.read'], 'Wallet': ['wallet.view'],
};

/// A titled block: the same plain header + "View all" link the Company Admin Home uses.
class WsSection extends StatelessWidget {
  const WsSection({super.key, required this.title, required this.child, this.action, this.onAction, this.perms});
  final String title;

  /// Hidden unless the user holds one of these permissions.
  final List<String>? perms;
  final Widget child;
  final String? action;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => !wsAllowed(perms) ? const SizedBox.shrink() : Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SectionHeader(title, action: action == null ? null : TextButton(onPressed: onAction, child: Text(action!))),
          child,
        ]),
      );
}

/// The purple summary block directly under the Home header (same colour and radius as the Company Admin hero target card).
class WsSummary extends StatelessWidget {
  const WsSummary({super.key, required this.title, required this.value, this.suffix, this.progress, this.footer, this.badge, this.actions = const []});
  final String title, value;
  final String? suffix, footer, badge;
  final double? progress;
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        color: M.heroBg,
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 22),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(title, style: const TextStyle(fontSize: 11, color: M.heroMuted))),
              if (badge != null) Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(99)), child: Text(badge!, style: const TextStyle(fontSize: 10.5, color: Colors.white, fontWeight: FontWeight.w600))),
            ]),
            const SizedBox(height: 2),
            RichText(
              text: TextSpan(style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: Colors.white), children: [
                TextSpan(text: value),
                if (suffix != null) TextSpan(text: ' $suffix', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: M.heroMuted)),
              ]),
            ),
            if (progress != null) ...[
              const SizedBox(height: 10),
              ClipRRect(borderRadius: BorderRadius.circular(99), child: LinearProgressIndicator(value: progress!.isNaN ? 0 : progress!.clamp(0, 1).toDouble(), minHeight: 6, backgroundColor: Colors.white.withValues(alpha: 0.15), valueColor: const AlwaysStoppedAnimation(M.heroRing))),
            ],
            if (footer != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(footer!, style: const TextStyle(fontSize: 11, color: M.heroMuted))),
            if (actions.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 12), child: Row(children: [for (var i = 0; i < actions.length; i++) ...[if (i > 0) const SizedBox(width: 8), Expanded(child: actions[i])]])),
          ]),
        ),
      );
}

/// Light button for the summary block.
class WsHeroButton extends StatelessWidget {
  const WsHeroButton(this.label, this.onTap, {super.key, this.filled = true});
  final String label;
  final VoidCallback onTap;
  final bool filled;
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(color: filled ? Colors.white : Colors.transparent, borderRadius: BorderRadius.circular(10), border: filled ? null : Border.all(color: Colors.white38)),
          child: Center(child: Text(label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: filled ? M.heroBg : Colors.white))),
        ),
      );
}

typedef WsTile = (String label, String value, String sub, Tint tint, VoidCallback? onTap);

/// Pastel stat tiles, two per row — the same tiles as the Company Admin Home's stat strip.
class WsTiles extends StatelessWidget {
  const WsTiles(this.items, {super.key});
  final List<WsTile> items;
  @override
  Widget build(BuildContext context) {
    final shown = [for (final t in items) if (wsAllowed(_tilePerms[t.$1])) t];
    if (shown.isEmpty) return const SizedBox.shrink();
    final w = (MediaQuery.of(context).size.width - 32 - 8) / 2;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Wrap(spacing: 8, runSpacing: 8, children: [
        for (final t in shown)
          GestureDetector(
            onTap: t.$5,
            child: Container(
              width: w,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              decoration: BoxDecoration(color: t.$4.$1, borderRadius: BorderRadius.circular(12)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t.$2, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600, color: t.$4.$2)),
                const SizedBox(height: 1),
                Text(t.$1, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: t.$4.$3)),
                Text(t.$3, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10.5, color: t.$4.$3)),
              ]),
            ),
          ),
      ]),
    );
  }
}

/// A row of small pastel chips (like the Pipeline stages): label + count.
class WsChips extends StatelessWidget {
  const WsChips(this.items, {super.key});
  final List<(String label, String value, Tint tint)> items;
  @override
  Widget build(BuildContext context) => SizedBox(
        height: 62,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, i) {
            final s = items[i];
            return Container(
              width: 96,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: s.$3.$1, borderRadius: BorderRadius.circular(12)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.$2, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: s.$3.$2)),
                Text(s.$1, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: s.$3.$3)),
              ]),
            );
          },
        ),
      );
}

/// Soft rounded card holding [rows] separated by hairlines (the Profile / Settings list look).
class WsRows extends StatelessWidget {
  const WsRows(this.rows, {super.key, this.empty = 'Nothing here yet.'});
  final List<Widget> rows;
  final String empty;
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        decoration: BoxDecoration(color: context.altSurface, borderRadius: BorderRadius.circular(12)),
        child: rows.isEmpty
            ? Padding(padding: const EdgeInsets.all(14), child: Text(empty, style: TextStyle(fontSize: 12.5, color: context.mutedColor)))
            : Column(children: [
                for (var i = 0; i < rows.length; i++)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                    decoration: BoxDecoration(border: i < rows.length - 1 ? Border(bottom: BorderSide(color: context.lineColor)) : null),
                    child: rows[i],
                  ),
              ]),
      );
}

/// One list row: avatar / leading, title + subtitle, trailing.
class WsRow extends StatelessWidget {
  const WsRow({super.key, required this.title, this.subtitle, this.leading, this.trailing, this.onTap});
  final String title;
  final String? subtitle;
  final Widget? leading, trailing;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Row(children: [
          if (leading != null) ...[leading!, const SizedBox(width: 12)],
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              if (subtitle != null) Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: context.mutedColor)),
            ]),
          ),
          if (trailing != null) trailing!,
        ]),
      );
}

class WsAvatar extends StatelessWidget {
  const WsAvatar(this.name, {super.key, this.size = 36});
  final String name;
  final double size;
  @override
  Widget build(BuildContext context) {
    final t = name.trim().isEmpty ? '?' : name.trim().split(' ').where((w) => w.isNotEmpty).map((w) => w[0].toUpperCase()).take(2).join();
    return CircleAvatar(radius: size / 2, backgroundColor: M.lavenderBg, child: Text(t, style: TextStyle(fontSize: size * 0.34, fontWeight: FontWeight.w600, color: M.lavenderMuted)));
  }
}

/// Small coloured status text, e.g. "Overdue", "On leave".
class WsBadge extends StatelessWidget {
  const WsBadge(this.text, this.tint, {super.key});
  final String text;
  final Tint tint;
  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: tint.$1, borderRadius: BorderRadius.circular(99)), child: Text(text, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: tint.$2)));
}

/// Round icon button used for call / WhatsApp / approve / reject.
class WsIconBtn extends StatelessWidget {
  const WsIconBtn(this.icon, this.onTap, {super.key, this.fg, this.bg});
  final IconData icon;
  final VoidCallback onTap;
  final Color? fg, bg;
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(width: 34, height: 34, decoration: BoxDecoration(color: bg ?? context.lineColor.withValues(alpha: 0.35), shape: BoxShape.circle), child: Icon(icon, size: 17, color: fg)),
      );
}

/// Shown at the top when a workspace's data could not be loaded, so an empty Home always says why.
class WsLoadError extends StatelessWidget {
  const WsLoadError(this.error, this.onRetry, {super.key});
  final Object? error;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: M.redBg, borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          const Icon(Icons.error_outline_rounded, color: M.redMuted, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(apiErrorMessage(error ?? 'Could not load this workspace.'), style: const TextStyle(color: M.redTitle, fontSize: 12.5))),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ]),
      );
}
