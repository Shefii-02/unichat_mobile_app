// ignore_for_file: use_build_context_synchronously
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:unichat_mobile_app/features/modules/module_providers.dart";
import "package:unichat_mobile_app/features/modules/_shared.dart";

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
