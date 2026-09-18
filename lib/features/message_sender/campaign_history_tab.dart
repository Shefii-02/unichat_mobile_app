import 'package:flutter/material.dart';
import 'package:unichat_mobile_app/features/modules/_shared.dart';

/// The "🕐 History" tab of the campaign sender — lists every `MessageSenderJob` for the company
/// (`GET /message-sender`, `MessageSenderController::index`) with live-merged per-recipient status
/// once any exist, and the same status-driven actions the web history table offers (Launch / Pause
/// / Resume / Stop / Delete). Duplicate-from-history and CSV export are not ported — status actions
/// and delivery details are the operationally useful part of this tab.
class CampaignHistoryTab extends StatefulWidget {
  const CampaignHistoryTab({super.key});
  @override
  State<CampaignHistoryTab> createState() => _CampaignHistoryTabState();
}

class _CampaignHistoryTabState extends State<CampaignHistoryTab> {
  List<Rec> _jobs = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final jobs = await Api.list('/message-sender');
      if (!mounted) return;
      setState(() { _jobs = jobs; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = apiErrorMessage(e); _loading = false; });
    }
  }

  Future<void> _action(Rec job, String action) async {
    final id = job['id'];
    final ok = await runAction(
      context,
      () => action == 'delete' ? Api.delete('/message-sender/$id') : Api.post('/message-sender/$id/$action'),
      success: switch (action) {
        'launch' => 'Campaign launched',
        'pause' => 'Campaign paused',
        'resume' => 'Campaign resumed',
        'stop' => 'Campaign stopped',
        'delete' => 'Campaign deleted',
        _ => 'Done',
      },
    );
    if (ok) _load();
  }

  void _showDetails(Rec job) {
    final log = (job['log'] as List?)?.cast<Rec>() ?? [];
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (ctx, scrollCtrl) => Column(
          children: [
            const SizedBox(height: 10),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: context.lineColor, borderRadius: BorderRadius.circular(2))),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 6),
              child: Row(children: [
                Expanded(
                  child: Text(str(job['campaign_name'], 'Campaign #${job['id']}'),
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                ),
                IconButton(onPressed: () => Navigator.of(ctx).pop(), icon: const Icon(Icons.close_rounded)),
              ]),
            ),
            Expanded(
              child: log.isEmpty
                  ? Center(child: Text('No delivery log yet', style: TextStyle(color: context.mutedColor)))
                  : ListView.separated(
                      controller: scrollCtrl,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: log.length,
                      separatorBuilder: (_, __) => Divider(height: 1, color: context.lineColor),
                      itemBuilder: (_, i) {
                        final l = log[i];
                        final status = str(l['status'], 'pending');
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(str(l['recipient_name'], str(l['phone'], 'Recipient')), style: const TextStyle(fontSize: 13)),
                          subtitle: Text(str(l['phone'], ''), style: TextStyle(fontSize: 11, color: context.mutedColor)),
                          trailing: StatusPill(status, color: _statusColor(status)),
                          isThreeLine: l['error'] != null,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Color _statusColor(String status) => switch (status) {
        'sent' || 'done' || 'delivered' => AppPalette.success,
        'failed' => AppPalette.danger,
        'running' || 'sending' || 'processing' => AppPalette.info,
        'paused' => AppPalette.warning,
        _ => AppPalette.muted,
      };

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text("Couldn't load history — $_error", textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _load, child: const Text('Retry')),
          ]),
        ),
      );
    }
    if (_jobs.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(children: [
          const SizedBox(height: 80),
          Center(
            child: Column(children: [
              Icon(Icons.campaign_outlined, size: 40, color: context.mutedColor.withValues(alpha: 0.4)),
              const SizedBox(height: 10),
              Text('No campaigns yet', style: TextStyle(color: context.mutedColor)),
            ]),
          ),
        ]),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _jobs.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) => _jobCard(_jobs[i]),
      ),
    );
  }

  Widget _jobCard(Rec job) {
    final status = str(job['status'], 'pending');
    final total = (num.tryParse('${job['total'] ?? 0}') ?? 0).toInt();
    final sent = (num.tryParse('${job['sent'] ?? 0}') ?? 0).toInt();
    final failed = (num.tryParse('${job['failed'] ?? 0}') ?? 0).toInt();
    final pending = (total - sent - failed).clamp(0, total);
    final sessionName = str(job['session_name'], str(job['session_id'], ''));
    final when_ = str(job['scheduled_at'] ?? job['started_at'] ?? job['created_at'], '');

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(border: Border.all(color: context.lineColor), borderRadius: BorderRadius.circular(10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Text('📢', style: TextStyle(fontSize: 16)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(str(job['campaign_name'], 'Campaign #${job['id']}'),
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5), maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            StatusPill(status, color: _statusColor(status)),
          ]),
          const SizedBox(height: 4),
          Text('${str(job['type'], '')} · $total recipient(s) · $sessionName',
              style: TextStyle(fontSize: 11.5, color: context.mutedColor)),
          if (when_.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(when(when_), style: TextStyle(fontSize: 11, color: context.mutedColor)),
            ),
          const SizedBox(height: 8),
          Wrap(spacing: 10, children: [
            _statChip('✅', sent, AppPalette.success),
            _statChip('⏳', pending, context.mutedColor),
            _statChip('❌', failed, AppPalette.danger),
          ]),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: total > 0 ? (sent + failed) / total : 0,
              backgroundColor: context.altSurface,
              minHeight: 5,
            ),
          ),
          const SizedBox(height: 8),
          Row(children: [
            TextButton(onPressed: () => _showDetails(job), child: const Text('Details')),
            const Spacer(),
            if (status == 'pending' || status == 'scheduled')
              TextButton(onPressed: () => _action(job, 'launch'), child: const Text('Launch')),
            if (status == 'running' || status == 'sending' || status == 'processing')
              TextButton(onPressed: () => _action(job, 'pause'), child: const Text('Pause')),
            if (status == 'paused') TextButton(onPressed: () => _action(job, 'resume'), child: const Text('Resume')),
            if (status != 'stopped' && status != 'done' && status != 'failed')
              TextButton(onPressed: () => _action(job, 'stop'), child: const Text('Stop')),
            if (status == 'stopped' || status == 'done' || status == 'failed')
              IconButton(
                tooltip: 'Delete',
                onPressed: () async {
                  if (await confirm(context, title: 'Delete this campaign?', destructive: true, confirmLabel: 'Delete')) {
                    _action(job, 'delete');
                  }
                },
                icon: const Icon(Icons.delete_outline_rounded, size: 20, color: AppPalette.danger),
              ),
          ]),
        ],
      ),
    );
  }

  Widget _statChip(String emoji, int count, Color color) => Row(mainAxisSize: MainAxisSize.min, children: [
        Text(emoji, style: const TextStyle(fontSize: 12)),
        const SizedBox(width: 3),
        Text('$count', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
      ]);
}
