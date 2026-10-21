// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:unichat_mobile_app/features/campaigns/presentation/pages/campaign_create_page.dart';
import 'package:unichat_mobile_app/features/modules/_shared.dart';

/// WA Cloud (Meta API) campaigns — same list the web "Campaigns" page shows. Creating a campaign
/// (template, number, audience), follow progress, edit a campaign that has not started,
/// launch / pause / resume, and delete.
class CampaignsPage extends StatefulWidget {
  const CampaignsPage({super.key});
  @override
  State<CampaignsPage> createState() => _CampaignsPageState();
}

class _CampaignsPageState extends State<CampaignsPage> {
  List<Rec> _campaigns = [];
  bool _loading = true;
  String? _error;
  String? _status;

  static const _statuses = ['draft', 'scheduled', 'running', 'paused', 'completed', 'failed'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final rows = await Api.list('/campaigns', query: {'per_page': 50, if (_status != null) 'status': _status});
      if (mounted) setState(() { _campaigns = rows; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = apiErrorMessage(e); _loading = false; });
    }
  }

  num _n(Object? v) => num.tryParse('${v ?? 0}') ?? 0;

  /// "20 Oct, 9:00 PM" in the phone's local time.
  String _fmt(Object? iso) {
    final d = DateTime.tryParse('${iso ?? ''}')?.toLocal();
    if (d == null) return '—';
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    return '${d.day} ${m[d.month - 1]} ${d.year}, $h:${d.minute.toString().padLeft(2, '0')} ${d.hour >= 12 ? 'PM' : 'AM'}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Campaigns')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final created = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const CampaignCreatePage()));
          if (created == true) _load();
        },
        icon: const Icon(Icons.add_rounded),
        label: const Text('New'),
      ),
      body: Column(children: [
        SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(label: const Text('All'), selected: _status == null,
                    onSelected: (_) { setState(() => _status = null); _load(); }),
              ),
              for (final s in _statuses)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(label: Text(s[0].toUpperCase() + s.substring(1)), selected: _status == s,
                      onSelected: (_) { setState(() => _status = s); _load(); }),
                ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)))
                  : _campaigns.isEmpty
                      ? Center(child: Text('No campaigns', style: TextStyle(color: context.mutedColor)))
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView.separated(
                            padding: const EdgeInsets.all(12),
                            itemCount: _campaigns.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (_, i) => _card(_campaigns[i]),
                          ),
                        ),
        ),
      ]),
    );
  }

  Widget _card(Rec c) {
    final status = str(c['status'], 'draft');
    final stats = (c['stats'] is Map) ? (c['stats'] as Map) : const {};
    final template = (c['template'] is Map) ? (c['template'] as Map) : const {};
    final started = !const ['draft', 'scheduled'].contains(status);
    final id = (c['id'] as num).toInt();

    return RecordCard(
      title: str(c['name'], 'Campaign'),
      subtitle: [
        if (template['name'] != null) '${template['name']}',
        if (c['created_at'] != null) '${c['created_at']}'.split('T').first,
      ].join(' · '),
      leadingIcon: Icons.campaign_rounded,
      leadingColor: const Color(0xFFF5871F),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        StatusPill(status),
        RowMenu(items: [
          ('Stats', Icons.bar_chart_rounded, () => _stats(c)),
          if (status == 'draft') ('Launch', Icons.play_arrow_rounded, () => _action(id, 'launch', 'Campaign launching.')),
          if (status == 'running') ('Pause', Icons.pause_rounded, () => _action(id, 'pause', 'Paused.')),
          if (status == 'paused') ('Resume', Icons.play_arrow_rounded, () => _action(id, 'resume', 'Resumed.')),
          // editing only makes sense before any message has gone out
          if (status == 'draft' || status == 'scheduled') ('Edit', Icons.edit_rounded, () => _edit(c)),
          if (const ['draft', 'scheduled', 'paused', 'completed'].contains(status)) ('Delete', Icons.delete_outline_rounded, () => _delete(c)),
        ]),
      ]),
      onTap: () => _stats(c),
      footer: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (status == 'scheduled' && c['scheduled_at'] != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('🕒 Scheduled ${_fmt(c['scheduled_at'])}',
                  style: const TextStyle(color: AppPalette.info, fontWeight: FontWeight.w600, fontSize: 12)),
            ),
          if (started)
            Wrap(spacing: 12, children: [
              Text('✅ ${stats['delivery_rate'] ?? 0}%', style: const TextStyle(color: AppPalette.success, fontSize: 12)),
              Text('👁️ ${stats['read_rate'] ?? 0}%', style: const TextStyle(color: AppPalette.info, fontSize: 12)),
              if (_n(stats['failed']) > 0) Text('❌ ${stats['failed']}', style: const TextStyle(color: AppPalette.danger, fontSize: 12)),
            ])
          else
            Text('${c['estimated_contacts'] != null ? '~${c['estimated_contacts']}' : '—'} contacts',
                style: TextStyle(color: context.mutedColor, fontSize: 12)),
        ]),
      ),
    );
  }

  void _stats(Rec c) {
    final s = (c['stats'] is Map) ? (c['stats'] as Map) : const {};
    final status = str(c['status'], 'draft');
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(str(c['name']), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            KvRow('Status', status),
            if (status == 'scheduled') KvRow('Scheduled for', _fmt(c['scheduled_at'])),
            KvRow('Contacts', str(s['total_contacts'])),
            KvRow('Sent', str(s['sent'])),
            KvRow('Delivered', '${s['delivered'] ?? 0} (${s['delivery_rate'] ?? 0}%)'),
            KvRow('Read', '${s['read'] ?? 0} (${s['read_rate'] ?? 0}%)'),
            KvRow('Failed', str(s['failed']), valueColor: _n(s['failed']) > 0 ? AppPalette.danger : null),
            KvRow('Pending', str(s['pending'])),
          ]),
        ),
      ),
    );
  }

  Future<void> _action(int id, String action, String ok) async {
    if (await runAction(context, () => Api.post('/campaigns/$id/$action'), success: ok)) _load();
  }

  Future<void> _delete(Rec c) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete campaign?'),
        content: Text('Delete "${str(c['name'])}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (yes != true) return;
    if (await runAction(context, () => Api.delete('/campaigns/${c['id']}'), success: 'Deleted.')) _load();
  }

  /// The only parts of a campaign that can change before it starts: when it sends, and the lead window
  /// (replies arriving between "from" and "to" are credited to it). Everything else is shown read-only.
  Future<void> _edit(Rec c) async {
    DateTime? local(Object? v) => v == null ? null : DateTime.tryParse('$v')?.toLocal();
    DateTime? at = local(c['scheduled_at']);
    DateTime? from = local(c['starts_at']);
    DateTime? to = local(c['ends_at']);
    final template = c['template'] is Map ? c['template'] as Map : const {};
    final number = c['wa_phone_number'] is Map ? c['wa_phone_number'] as Map : const {};
    final labels = c['target_labels'] is List ? (c['target_labels'] as List).length : 0;
    final target = switch ('${c['target_type']}') {
      'all' => 'All opted-in contacts',
      'labels' => '$labels label(s)',
      'csv' => 'CSV list',
      final t => t,
    };
    final daily = num.tryParse('${c['daily_limit'] ?? ''}');
    var saving = false;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        Widget box(String label, String value) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: Theme.of(ctx).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(12), border: Border.all(color: ctx.lineColor)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label.toUpperCase(), style: TextStyle(fontSize: 10, letterSpacing: 0.5, color: ctx.mutedColor)),
                const SizedBox(height: 2),
                Text(value.isEmpty ? '—' : value, style: const TextStyle(fontWeight: FontWeight.w600)),
              ]),
            );

        Widget picker(String label, DateTime? value, String Function(DateTime) fmt, Future<DateTime?> Function() pick, void Function(DateTime) onPicked, VoidCallback clear) => FField(
              label: label,
              child: Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.event_rounded, size: 18),
                    label: Text(value == null ? 'Not set' : fmt(value)),
                    onPressed: () async {
                      final d = await pick();
                      if (d != null) setS(() => onPicked(d));
                    },
                  ),
                ),
                if (value != null) IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => setS(clear)),
              ]),
            );

        String dateOnly(DateTime d) => '${d.day}/${d.month}/${d.year}';
        final now = DateTime.now();

        // The Save button is pinned below the scrolling content so it is always reachable, even on a short screen.
        return Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(ctx).viewInsets.bottom + 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Flexible(
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Edit schedule', style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text('Only the send time and the lead dates can be changed. The rest is fixed once a campaign is created.', style: TextStyle(color: ctx.mutedColor, fontSize: 12)),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final e in <(String, String)>[
                  ('Campaign name', str(c['name'], '')),
                  ('Status', str(c['status'], '')),
                  ('Template', str(template['name'], '')),
                  ('Sending number', str(number['display_phone_number'] ?? number['label'], '')),
                  ('Target', target),
                  ('Speed', '${c['throttle_per_minute'] ?? 60} msgs/min'),
                  ('Daily limit', daily == null ? 'No limit' : '$daily per day'),
                  if (str(c['description'], '').isNotEmpty) ('Description', str(c['description'], '')),
                ])
                  SizedBox(width: (MediaQuery.of(ctx).size.width - 48) / 2, child: box(e.$1, e.$2)),
              ]),
              const SizedBox(height: 16),
              picker(
                'Send at', at, (d) => _fmt(d.toIso8601String()),
                () async {
                  final d = await showDatePicker(context: ctx, initialDate: (at != null && at!.isAfter(now)) ? at! : now.add(const Duration(hours: 1)), firstDate: now, lastDate: now.add(const Duration(days: 365)));
                  if (d == null) return null;
                  final t = await showTimePicker(context: ctx, initialTime: TimeOfDay.fromDateTime(at ?? now.add(const Duration(hours: 1))));
                  return t == null ? null : DateTime(d.year, d.month, d.day, t.hour, t.minute);
                },
                (d) => at = d,
                () => at = null,
              ),
              Text(at == null ? 'No send time: launch it yourself from the list.' : 'It launches automatically at this time.', style: TextStyle(color: ctx.mutedColor, fontSize: 11)),
              const SizedBox(height: 8),
              picker(
                'Lead from', from, dateOnly,
                () => showDatePicker(context: ctx, initialDate: from ?? now, firstDate: DateTime(now.year - 1), lastDate: DateTime(now.year + 3)),
                (d) => from = d,
                () => from = null,
              ),
              picker(
                'Lead to', to, dateOnly,
                () => showDatePicker(context: ctx, initialDate: to ?? from ?? now, firstDate: from ?? DateTime(now.year - 1), lastDate: DateTime(now.year + 3)),
                (d) => to = d,
                () => to = null,
              ),
              Text('A reply arriving between these dates is credited to this campaign in its stats.', style: TextStyle(color: ctx.mutedColor, fontSize: 11)),
                ]),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: saving
                      ? null
                      : () async {
                          if (at != null && !at!.isAfter(DateTime.now())) {
                            ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Send time must be in the future.')));
                            return;
                          }
                          if (from != null && to != null && to!.isBefore(from!)) {
                            ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Lead end date must be on or after the start date.')));
                            return;
                          }
                          setS(() => saving = true);
                          final ok = await runAction(ctx, () => Api.put('/campaigns/${c['id']}', data: {
                                'scheduled_at': at?.toUtc().toIso8601String(),
                                'starts_at': from == null ? null : _isoDate(from!),
                                'ends_at': to == null ? null : _isoDate(to!),
                              }), success: 'Campaign updated.');
                          if (ctx.mounted) {
                            setS(() => saving = false);
                            if (ok) Navigator.of(ctx).pop(true);
                          }
                        },
                  child: Text(saving ? 'Saving…' : 'Save'),
                ),
            ),
          ]),
        );
      }),
    );
    if (saved == true) _load();
  }

  String _isoDate(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

}
