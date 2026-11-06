import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:unichat_mobile_app/features/modules/module_providers.dart';
import 'package:unichat_mobile_app/features/modules/_shared.dart';

/// Node-based Instagram flows (comment → public reply → DM → follower check → …). The canvas is
/// built on the web portal; here you can monitor, switch on/off, and see who is mid-flow.
class InstagramFlowsPage extends ConsumerWidget {
  const InstagramFlowsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Instagram Flows')),
      body: ProviderList(
        provider: igFlowsProvider,
        emptyLabel: 'No flows yet — build one on the web portal',
        emptyIcon: Icons.account_tree_rounded,
        tile: (context, f) {
          final active = f['is_active'] == true;
          final waiting = int.tryParse('${f['waiting_runs_count'] ?? 0}') ?? 0;
          return RecordCard(
            title: str(f['name'], 'Flow'),
            subtitle:
                '${f['trigger_type'] == 'dm' ? 'DM keyword' : 'Comment'} · started ${f['triggered_count'] ?? 0}×${waiting > 0 ? ' · $waiting waiting' : ''}',
            leadingIcon: Icons.account_tree_rounded,
            leadingColor: const Color(0xFFE1306C),
            onTap: () => _runs(context, f),
            trailing: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                StatusPill(active ? 'active' : 'draft'),
                RowMenu(items: [
                  (
                    active ? 'Pause' : 'Activate',
                    active ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    () async {
                      final ok = await runAction(context,
                          () => Api.post('/instagram/flows/${f['id']}/toggle'),
                          success: 'Updated');
                      if (ok) ref.invalidate(igFlowsProvider);
                    }
                  ),
                  ('Recent runs', Icons.history_rounded, () => _runs(context, f)),
                  (
                    'Delete',
                    Icons.delete_rounded,
                    () async {
                      if (!await confirm(context,
                          title: 'Delete flow?',
                          destructive: true,
                          confirmLabel: 'Delete')) { return; }
                      final ok = await runAction(context,
                          () => Api.delete('/instagram/flows/${f['id']}'),
                          success: 'Deleted');
                      if (ok) ref.invalidate(igFlowsProvider);
                    }
                  ),
                ]),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _runs(BuildContext context, Rec f) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SizedBox(
        height: MediaQuery.of(ctx).size.height * 0.7,
        child: FutureBuilder<List<Rec>>(
          future: Api.list('/instagram/flows/${f['id']}/runs'),
          builder: (ctx, snap) {
            final runs = snap.data ?? const <Rec>[];
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              children: [
                Text(str(f['name']),
                    style: Theme.of(ctx)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text('Recent runs', style: TextStyle(color: ctx.mutedColor)),
                const SizedBox(height: 10),
                if (snap.connectionState != ConnectionState.done)
                  const Center(child: CircularProgressIndicator())
                else if (runs.isEmpty)
                  Text('Nobody has gone through this flow yet.',
                      style: TextStyle(color: ctx.mutedColor)),
                for (final r in runs)
                  RecordCard(
                    title:
                        '@${str((r['conversation'] as Map?)?['participant_username'] ?? r['igsid'])}',
                    subtitle: r['error'] != null
                        ? str(r['error'])
                        : '${str(r['wait_kind'], '')} ${when(r['created_at'])}'.trim(),
                    leadingIcon: Icons.person_rounded,
                    leadingColor: const Color(0xFFE1306C),
                    trailing: StatusPill(str(r['status'])),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
