// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'module_providers.dart';
import '_shared.dart';

const _igPink = Color(0xFFE1306C);

/// Shared account picker used by both Comments and Insights — Instagram
/// features are always scoped to one connected account at a time.
class _AccountPickerBar extends StatelessWidget {
  const _AccountPickerBar({required this.accounts, required this.selected, required this.onSelect});
  final List<Rec> accounts;
  final Rec? selected;
  final void Function(Rec) onSelect;

  @override
  Widget build(BuildContext context) {
    if (accounts.length <= 1) return const SizedBox.shrink();
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        itemCount: accounts.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final a = accounts[i];
          final sel = selected?['id'] == a['id'];
          return ChoiceChip(
            label: Text('@${str(a['username'], 'account')}'),
            selected: sel,
            onSelected: (_) => onSelect(a),
          );
        },
      ),
    );
  }
}

// ══════════════════════════ Comments ══════════════════════════

class InstagramCommentsPage extends ConsumerStatefulWidget {
  const InstagramCommentsPage({super.key});
  @override
  ConsumerState<InstagramCommentsPage> createState() => _InstagramCommentsPageState();
}

class _InstagramCommentsPageState extends ConsumerState<InstagramCommentsPage> {
  Rec? _account;

  @override
  Widget build(BuildContext context) {
    final accountsAsync = ref.watch(igAccountsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Instagram Comments')),
      body: accountsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(apiErrorMessage(e))),
        data: (accounts) {
          if (accounts.isEmpty) {
            return Center(child: Text('No Instagram accounts connected', style: TextStyle(color: context.mutedColor)));
          }
          _account ??= accounts.first;
          final accountId = _account!['id'] as int;
          return Column(
            children: [
              _AccountPickerBar(accounts: accounts, selected: _account, onSelect: (a) => setState(() => _account = a)),
              Expanded(
                child: Consumer(
                  builder: (context, ref, _) {
                    final mediaAsync = ref.watch(igAccountMediaProvider(accountId));
                    return mediaAsync.when(
                      loading: () => const Center(child: CircularProgressIndicator()),
                      error: (e, _) => Center(child: Text(apiErrorMessage(e))),
                      data: (media) => media.isEmpty
                          ? Center(child: Text('No posts found for this account', style: TextStyle(color: context.mutedColor)))
                          : ListView.separated(
                              padding: const EdgeInsets.all(12),
                              itemCount: media.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 8),
                              itemBuilder: (_, i) {
                                final m = media[i];
                                final thumb = m['thumbnail_url'] ?? m['media_url'];
                                return Card(
                                  child: ListTile(
                                    leading: thumb != null
                                        ? ClipRRect(borderRadius: BorderRadius.circular(8),
                                            child: Image.network('$thumb', width: 44, height: 44, fit: BoxFit.cover,
                                                errorBuilder: (_, __, ___) => const Icon(Icons.image_not_supported_outlined)))
                                        : const Icon(Icons.image_rounded, color: _igPink),
                                    title: Text(str(m['caption'], 'No caption'), maxLines: 1, overflow: TextOverflow.ellipsis),
                                    subtitle: Text('${m['like_count'] ?? 0} likes · ${m['comments_count'] ?? 0} comments · ${when(m['timestamp'])}'),
                                    trailing: const Icon(Icons.chevron_right_rounded),
                                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                                        builder: (_) => _CommentsThreadPage(accountId: accountId, mediaId: '${m['id']}'))),
                                  ),
                                );
                              },
                            ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CommentsThreadPage extends StatefulWidget {
  const _CommentsThreadPage({required this.accountId, required this.mediaId});
  final int accountId;
  final String mediaId;
  @override
  State<_CommentsThreadPage> createState() => _CommentsThreadPageState();
}

class _CommentsThreadPageState extends State<_CommentsThreadPage> {
  List<Rec> _comments = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await Api.one('/instagram/accounts/${widget.accountId}/media/${widget.mediaId}/comments');
      final comments = res['comments'];
      setState(() {
        _comments = comments is List ? comments.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList() : [];
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _reply(String commentId) async {
    final data = <String, dynamic>{};
    final ok = await showFormSheet(
      context,
      title: 'Reply to comment',
      submitLabel: 'Post reply',
      fields: (ctx) => [
        FText(label: 'Reply', required: true, maxLines: 3, onSaved: (v) => data['text'] = v),
      ],
      onSubmit: () => Api.post('/instagram/accounts/${widget.accountId}/comments/$commentId/reply', data: data),
    );
    if (ok) _load();
  }

  Future<void> _toggleHide(String commentId, bool currentlyHidden) async {
    final ok = await runAction(context,
        () => Api.post('/instagram/accounts/${widget.accountId}/comments/$commentId/hide', data: {'hide': !currentlyHidden}),
        success: currentlyHidden ? 'Comment unhidden' : 'Comment hidden');
    if (ok) _load();
  }

  Future<void> _delete(String commentId) async {
    final sure = await confirm(context, title: 'Delete this comment?', destructive: true, confirmLabel: 'Delete');
    if (!sure) return;
    final ok = await runAction(context, () => Api.delete('/instagram/accounts/${widget.accountId}/comments/$commentId'), success: 'Deleted');
    if (ok) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Comments')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _comments.isEmpty
              ? Center(child: Text('No comments yet', style: TextStyle(color: context.mutedColor)))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: _comments.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (_, i) {
                      final c = _comments[i];
                      final replies = (c['replies'] is Map && (c['replies'] as Map)['data'] is List)
                          ? ((c['replies'] as Map)['data'] as List).whereType<Map>().toList()
                          : const [];
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _CommentRow(
                            comment: c,
                            onReply: () => _reply('${c['id']}'),
                            onToggleHide: () => _toggleHide('${c['id']}', c['hidden'] == true),
                            onDelete: () => _delete('${c['id']}'),
                          ),
                          for (final r in replies)
                            Padding(
                              padding: const EdgeInsets.only(left: 32, top: 8),
                              child: _CommentRow(
                                comment: r.cast<String, dynamic>(),
                                onReply: () => _reply('${r['id']}'),
                                onToggleHide: () => _toggleHide('${r['id']}', r['hidden'] == true),
                                onDelete: () => _delete('${r['id']}'),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
    );
  }
}

class _CommentRow extends StatelessWidget {
  const _CommentRow({required this.comment, required this.onReply, required this.onToggleHide, required this.onDelete});
  final Rec comment;
  final VoidCallback onReply;
  final VoidCallback onToggleHide;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final hidden = comment['hidden'] == true;
    return Card(
      color: hidden ? context.altSurface : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text('@${str(comment['username'], 'user')}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              ),
              if (hidden) const StatusPill('hidden'),
              Text(when(comment['timestamp']), style: TextStyle(fontSize: 11, color: context.mutedColor)),
            ]),
            const SizedBox(height: 4),
            Text(str(comment['text'])),
            const SizedBox(height: 8),
            Row(children: [
              TextButton(onPressed: onReply, child: const Text('Reply')),
              TextButton(onPressed: onToggleHide, child: Text(hidden ? 'Unhide' : 'Hide')),
              TextButton(onPressed: onDelete, child: const Text('Delete', style: TextStyle(color: AppPalette.danger))),
            ]),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════ Insights ══════════════════════════

const _igMetricLabels = {
  'reach': 'Reach',
  'accounts_engaged': 'Accounts engaged',
  'profile_views': 'Profile views',
  'follower_count': 'Follower change',
};

class InstagramInsightsPage extends ConsumerStatefulWidget {
  const InstagramInsightsPage({super.key});
  @override
  ConsumerState<InstagramInsightsPage> createState() => _InstagramInsightsPageState();
}

class _InstagramInsightsPageState extends ConsumerState<InstagramInsightsPage> {
  Rec? _account;

  @override
  Widget build(BuildContext context) {
    final accountsAsync = ref.watch(igAccountsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Instagram Insights')),
      body: accountsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(apiErrorMessage(e))),
        data: (accounts) {
          if (accounts.isEmpty) {
            return Center(child: Text('No Instagram accounts connected', style: TextStyle(color: context.mutedColor)));
          }
          _account ??= accounts.first;
          final accountId = _account!['id'] as int;
          return Column(
            children: [
              _AccountPickerBar(accounts: accounts, selected: _account, onSelect: (a) => setState(() => _account = a)),
              Expanded(
                child: Consumer(
                  builder: (context, ref, _) {
                    final insightsAsync = ref.watch(igAccountInsightsProvider(accountId));
                    return RefreshIndicator(
                      onRefresh: () async => ref.invalidate(igAccountInsightsProvider(accountId)),
                      child: insightsAsync.when(
                        loading: () => const Center(child: CircularProgressIndicator()),
                        error: (e, _) => ListView(children: [
                          const SizedBox(height: 80),
                          Center(child: Text("Couldn't load insights — ${apiErrorMessage(e)}", textAlign: TextAlign.center)),
                        ]),
                        data: (insights) {
                          final rows = (insights['data'] is List) ? insights['data'] as List : const [];
                          final byMetric = {for (final r in rows) if (r is Map) str(r['name']): r};
                          num sumOf(String metric) {
                            final m = byMetric[metric];
                            final values = (m?['values'] is List) ? m!['values'] as List : const [];
                            return values.fold<num>(0, (s, v) => s + (num.tryParse('${(v as Map)['value'] ?? 0}') ?? 0));
                          }

                          return ListView(
                            padding: const EdgeInsets.all(16),
                            children: [
                              Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(color: context.altSurface, borderRadius: BorderRadius.circular(14)),
                                child: Row(children: [
                                  CircleAvatar(
                                    radius: 24,
                                    backgroundColor: _igPink.withValues(alpha: 0.15),
                                    backgroundImage: _account!['profile_picture_url'] != null
                                        ? NetworkImage('${_account!['profile_picture_url']}')
                                        : null,
                                    child: _account!['profile_picture_url'] == null
                                        ? const Icon(Icons.person_rounded, color: _igPink)
                                        : null,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('@${str(_account!['username'], 'account')}', style: const TextStyle(fontWeight: FontWeight.w700)),
                                        Text('${compact(_account!['followers_count'])} followers', style: TextStyle(color: context.mutedColor, fontSize: 12.5)),
                                      ],
                                    ),
                                  ),
                                ]),
                              ),
                              const SizedBox(height: 16),
                              if (rows.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 24),
                                  child: Center(child: Text('No data for this metric yet — Meta backfills a day or two after connecting.',
                                      textAlign: TextAlign.center, style: TextStyle(color: context.mutedColor))),
                                )
                              else ...[
                                StatGrid([
                                  ('Reach (14d)', compact(sumOf('reach')), Icons.visibility_rounded),
                                  ('Accounts engaged', compact(sumOf('accounts_engaged')), Icons.groups_rounded),
                                  ('Profile views', compact(sumOf('profile_views')), Icons.remove_red_eye_rounded),
                                  ('Follower change', compact(sumOf('follower_count')), Icons.person_add_alt_1_rounded),
                                ]),
                                const SizedBox(height: 20),
                                for (final entry in _igMetricLabels.entries)
                                  if (byMetric[entry.key] != null) _MetricTrend(label: entry.value, metric: byMetric[entry.key]!),
                              ],
                            ],
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _MetricTrend extends StatelessWidget {
  const _MetricTrend({required this.label, required this.metric});
  final String label;
  final Map metric;

  @override
  Widget build(BuildContext context) {
    final values = (metric['values'] is List) ? metric['values'] as List : const [];
    if (values.isEmpty) return const SizedBox.shrink();
    final nums = values.map((v) => num.tryParse('${(v as Map)['value'] ?? 0}') ?? 0).toList();
    final maxV = nums.fold<num>(1, (m, v) => v > m ? v : m);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 8),
          SizedBox(
            height: 70,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < values.length; i++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1.5),
                      child: Tooltip(
                        message: '${(values[i] as Map)['end_time'] ?? ''}: ${nums[i]}',
                        child: Container(
                          height: 4 + (nums[i] / maxV) * 60,
                          decoration: BoxDecoration(color: _igPink.withValues(alpha: 0.75), borderRadius: BorderRadius.circular(2)),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
