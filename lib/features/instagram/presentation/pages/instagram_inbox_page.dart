import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:unichat_mobile_app/features/modules/module_providers.dart';
import 'package:unichat_mobile_app/features/modules/_shared.dart';

/// Split out of the former shared `InstagramPage` (tab 0 "Inbox" + tab 2 "Accounts", which
/// had no catalogue tile of its own — kept alongside Inbox here rather than left unreachable).
/// Automations (tab 1) is its own catalogue tile and is now `InstagramAutomationsPage`.
class InstagramInboxPage extends ConsumerWidget {
  const InstagramInboxPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Instagram — SM Inbox'),
          bottom: const TabBar(tabs: [
            Tab(text: 'Inbox'),
            Tab(text: 'Accounts'),
          ]),
        ),
        body: TabBarView(children: [
          const _IgInboxTab(),
          ProviderList(
            provider: igAccountsProvider,
            emptyLabel: 'No Instagram accounts connected',
            emptyIcon: Icons.photo_camera_rounded,
            tile: (context, a) => RecordCard(
              title: '@${str(a['username'] ?? a['name'], 'account')}',
              subtitle:
                  '${compact(a['followers_count'])} followers${str(a['page_name'], '').isNotEmpty ? ' · ${a['page_name']}' : ''}',
              leadingIcon: Icons.photo_camera_rounded,
              leadingColor: const Color(0xFFE1306C),
              trailing: RowMenu(items: [
                (
                  'Sync',
                  Icons.sync_rounded,
                  () async {
                    final ok = await runAction(context,
                        () => Api.post('/instagram/accounts/${a['id']}/sync'),
                        success: 'Sync started');
                    if (ok) ref.invalidate(igAccountsProvider);
                  }
                ),
                (
                  'Import listings',
                  Icons.download_rounded,
                  () async {
                    final ok = await runAction(context,
                        () => Api.post('/instagram/accounts/${a['id']}/import-listings'),
                        success: 'Import queued');
                    if (ok) ref.invalidate(listingsProvider);
                  }
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  /// The conversation sheet (thread + reply). Public so "my chats" on the Sales home can open it too.
  Future<void> openConversation(BuildContext context, WidgetRef ref, Rec c) async {
    final controller = TextEditingController();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('@${str(c['participant_username'] ?? c['username'] ?? c['participant_id'])}',
                style: Theme.of(ctx)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const SizedBox(height: 8),
            // Whole thread — bot, flow, AI, staff and Instagram-app messages all land here.
            SizedBox(
              height: 260,
              child: FutureBuilder<Map<String, dynamic>>(
                future: Api.one('/instagram/conversations/${c['id']}'),
                builder: (ctx, snap) {
                  final msgs = ((snap.data?['messages'] as List?) ?? const [])
                      .whereType<Map>()
                      .toList();
                  if (snap.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (msgs.isEmpty) {
                    return Text('No messages yet.',
                        style: TextStyle(color: ctx.mutedColor));
                  }
                  const labels = {
                    'flow': 'Flow',
                    'automation': 'Automation',
                    'ai': 'AI agent',
                    'manual': 'You',
                    'staff_app': 'Instagram app',
                  };
                  return ListView(
                    children: [
                      for (final m in msgs)
                        Align(
                          alignment: m['direction'] == 'out'
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 3),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            constraints: BoxConstraints(
                                maxWidth: MediaQuery.of(ctx).size.width * 0.75),
                            decoration: BoxDecoration(
                              color: m['direction'] == 'out'
                                  ? const Color(0xFFE1306C)
                                  : Colors.grey.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(str(m['text'], ''),
                                    style: TextStyle(
                                        color: m['direction'] == 'out'
                                            ? Colors.white
                                            : null)),
                                if (m['direction'] == 'out' &&
                                    labels[m['source']] != null)
                                  Text(labels[m['source']]!,
                                      style: TextStyle(
                                          fontSize: 10,
                                          color: m['direction'] == 'out'
                                              ? Colors.white70
                                              : ctx.mutedColor)),
                              ],
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: controller,
              minLines: 1,
              maxLines: 4,
              decoration: const InputDecoration(hintText: 'Type a reply…'),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      await runAction(context,
                          () => Api.patch('/instagram/conversations/${c['id']}',
                              data: {'status': 'closed'}),
                          success: 'Marked closed');
                      ref.invalidate(igConversationsProvider);
                    },
                    child: const Text('Close chat'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: () async {
                      if (controller.text.trim().isEmpty) return;
                      Navigator.pop(ctx);
                      final ok = await runAction(
                        context,
                        () => Api.post('/instagram/conversations/${c['id']}/reply',
                            data: {'text': controller.text.trim()}),
                        success: 'Sent',
                      );
                      if (ok) ref.invalidate(igConversationsProvider);
                    },
                    child: const Text('Send'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}


/// The Instagram DM inbox with two tabs — All chats, or only the ones assigned to me (the open tab is underlined).
class _IgInboxTab extends ConsumerStatefulWidget {
  const _IgInboxTab();
  @override
  ConsumerState<_IgInboxTab> createState() => _IgInboxTabState();
}

class _IgInboxTabState extends ConsumerState<_IgInboxTab> {
  bool _mine = false;
  List<Rec>? _rows;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await Api.list('/instagram/conversations', query: {if (_mine) 'mine': 1});
      if (mounted) setState(() { _rows = rows; _error = null; });
    } catch (e) {
      if (mounted) setState(() => _error = apiErrorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Column(children: [
      Row(children: [
        for (final (label, mine) in [('All chats', false), ('Assigned to me', true)])
          Expanded(
            child: InkWell(
              onTap: () { if (_mine != mine) { setState(() { _mine = mine; _rows = null; }); _load(); } },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 11),
                alignment: Alignment.center,
                decoration: BoxDecoration(border: Border(bottom: BorderSide(color: _mine == mine ? primary : Colors.transparent, width: 2.5))),
                child: Text(label, style: TextStyle(fontWeight: _mine == mine ? FontWeight.w800 : FontWeight.w500, color: _mine == mine ? null : context.mutedColor)),
              ),
            ),
          ),
      ]),
      Expanded(
        child: _error != null
            ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [Text(_error!, textAlign: TextAlign.center), TextButton(onPressed: () { setState(() => _error = null); _load(); }, child: const Text('Try again'))])))
            : _rows == null
                ? const Center(child: CircularProgressIndicator())
                : _rows!.isEmpty
                    ? Center(child: Text(_mine ? 'Nothing is assigned to you here.' : 'No DM conversations', style: TextStyle(color: context.mutedColor)))
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.separated(
                          padding: const EdgeInsets.all(12),
                          itemCount: _rows!.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (context, i) {
                            final c = _rows![i];
                            return RecordCard(
                              title: str(c['participant_username'] ?? c['username'] ?? c['participant_id'], 'Conversation'),
                              subtitle: str(c['last_message_preview'] ?? c['last_message'] ?? c['preview']),
                              leadingIcon: Icons.person_rounded,
                              leadingColor: const Color(0xFFE1306C),
                              onTap: () => const InstagramInboxPage().openConversation(context, ref, c),
                              trailing: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                                Text(when(c['last_message_at'] ?? c['updated_at']), style: TextStyle(fontSize: 11, color: context.mutedColor)),
                                const SizedBox(height: 4),
                                StatusPill(str(c['status'], 'open')),
                              ]),
                            );
                          },
                        ),
                      ),
      ),
    ]);
  }
}
