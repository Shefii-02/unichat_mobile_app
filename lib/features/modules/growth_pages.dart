// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'module_providers.dart';
import '_shared.dart';

// ══════════════════════════ Meta Ads ══════════════════════════

class MetaAdsPage extends ConsumerWidget {
  const MetaAdsPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Meta Ads'),
          bottom: const TabBar(isScrollable: true, tabs: [
            Tab(text: 'Insights'),
            Tab(text: 'Campaigns'),
            Tab(text: 'Audience Sets'),
            Tab(text: 'Accounts'),
          ]),
        ),
        body: TabBarView(children: [
          ProviderObject(
            provider: metaInsightsOverviewProvider,
            builder: (context, d) {
              final items = <(String, String, IconData)>[
                ('Spend', money(d['spend'] ?? d['total_spend']), Icons.payments_rounded),
                ('Impressions', compact(d['impressions']), Icons.visibility_rounded),
                ('Clicks', compact(d['clicks']), Icons.ads_click_rounded),
                ('CTR', '${d['ctr'] ?? 0}%', Icons.percent_rounded),
                ('Leads', compact(d['leads'] ?? d['results']), Icons.person_add_alt_rounded),
                ('CPL', money(d['cpl'] ?? d['cost_per_lead']), Icons.request_quote_rounded),
              ];
              return ListView(children: [StatGrid(items)]);
            },
          ),
          ProviderList(
            provider: metaCampaignsProvider,
            emptyLabel: 'No campaigns',
            tile: (context, c) {
              final status = str(c['status'] ?? c['effective_status'], 'PAUSED');
              return RecordCard(
                title: str(c['name']),
                subtitle:
                    '${str(c['objective'])} · budget ${money(c['daily_budget'] ?? c['budget'] ?? c['lifetime_budget'])}',
                leadingIcon: Icons.campaign_rounded,
                leadingColor: const Color(0xFF1877F2),
                trailing: StatusPill(status),
                onTap: () => _campaignDetail(context, ref, c),
              );
            },
          ),
          ProviderList(
            provider: metaAudienceSetsProvider,
            emptyLabel: 'No saved audience sets',
            emptyIcon: Icons.groups_rounded,
            tile: (context, a) => RecordCard(
              title: str(a['name']),
              subtitle: str(a['description'] ?? a['summary'],
                  'Reusable targeting preset'),
              leadingIcon: Icons.groups_rounded,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (a['estimated_reach'] != null)
                    Text(compact(a['estimated_reach']),
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  RowMenu(items: [
                    (
                      'Duplicate',
                      Icons.copy_rounded,
                      () async {
                        final ok = await runAction(context,
                            () => Api.post('/meta-ads/audience-sets/${a['id']}/duplicate'),
                            success: 'Duplicated');
                        if (ok) ref.invalidate(metaAudienceSetsProvider);
                      }
                    ),
                    (
                      'Delete',
                      Icons.delete_rounded,
                      () async {
                        if (!await confirm(context,
                            title: 'Delete audience set?',
                            destructive: true,
                            confirmLabel: 'Delete')) { return; }
                        final ok = await runAction(context,
                            () => Api.delete('/meta-ads/audience-sets/${a['id']}'),
                            success: 'Deleted');
                        if (ok) ref.invalidate(metaAudienceSetsProvider);
                      }
                    ),
                  ]),
                ],
              ),
            ),
          ),
          ProviderList(
            provider: metaAccountsProvider,
            emptyLabel: 'No ad accounts linked',
            tile: (context, a) => RecordCard(
              title: str(a['name'] ?? a['account_name']),
              subtitle:
                  '${str(a['account_id'] ?? a['ad_account_id'])} · ${str(a['currency'])}',
              leadingIcon: Icons.account_box_rounded,
              trailing: (a['is_default'] == true)
                  ? const StatusPill('default')
                  : StatusPill(str(a['status'], 'active')),
              onTap: a['is_default'] == true
                  ? null
                  : () async {
                      final ok = await runAction(context,
                          () => Api.post('/meta-ads/accounts/${a['id']}/set-default'),
                          success: 'Set as default');
                      if (ok) ref.invalidate(metaAccountsProvider);
                    },
            ),
          ),
        ]),
      ),
    );
  }

  void _campaignDetail(BuildContext context, WidgetRef ref, Rec c) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(str(c['name']),
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              KvRow('Objective', str(c['objective'])),
              KvRow('Status', str(c['status'] ?? c['effective_status'])),
              KvRow('Daily budget', money(c['daily_budget'])),
              KvRow('Lifetime budget', money(c['lifetime_budget'])),
              KvRow('Special category', str(c['special_ad_categories'] ?? c['special_ad_category'], 'none')),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                children: [
                  for (final s in ['ACTIVE', 'PAUSED', 'ARCHIVED'])
                    OutlinedButton(
                      onPressed: () async {
                        Navigator.pop(context);
                        final ok = await runAction(
                          context,
                          () => Api.patch('/meta-ads/campaigns/${c['id']}/status',
                              data: {'status': s}),
                          success: 'Campaign $s',
                        );
                        if (ok) ref.invalidate(metaCampaignsProvider);
                      },
                      child: Text(s),
                    ),
                  OutlinedButton.icon(
                    onPressed: () async {
                      Navigator.pop(context);
                      final ok = await runAction(context,
                          () => Api.post('/meta-ads/campaigns/${c['id']}/duplicate'),
                          success: 'Duplicated');
                      if (ok) ref.invalidate(metaCampaignsProvider);
                    },
                    icon: const Icon(Icons.copy_rounded, size: 16),
                    label: const Text('Duplicate'),
                  ),
                  TextButton.icon(
                    onPressed: () async {
                      Navigator.pop(context);
                      if (!await confirm(context,
                          title: 'Delete campaign?',
                          destructive: true,
                          confirmLabel: 'Delete')) { return; }
                      final ok = await runAction(context,
                          () => Api.delete('/meta-ads/campaigns/${c['id']}'),
                          success: 'Deleted');
                      if (ok) ref.invalidate(metaCampaignsProvider);
                    },
                    icon: const Icon(Icons.delete_rounded,
                        size: 16, color: AppPalette.danger),
                    label: const Text('Delete',
                        style: TextStyle(color: AppPalette.danger)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════ Instagram ══════════════════════════

class InstagramPage extends ConsumerWidget {
  const InstagramPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Instagram'),
          bottom: const TabBar(tabs: [
            Tab(text: 'Inbox'),
            Tab(text: 'Automations'),
            Tab(text: 'Accounts'),
          ]),
        ),
        floatingActionButton: Builder(
          builder: (tabCtx) => FloatingActionButton.extended(
            onPressed: () => _editAutomation(tabCtx, ref, null),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Automation'),
          ),
        ),
        body: TabBarView(children: [
          ProviderList(
            provider: igConversationsProvider,
            emptyLabel: 'No DM conversations',
            emptyIcon: Icons.forum_rounded,
            tile: (context, c) => RecordCard(
              title: str(c['username'] ?? c['name'] ?? c['from'], 'Conversation'),
              subtitle: str(c['last_message'] ?? c['preview'] ?? c['snippet']),
              leadingIcon: Icons.person_rounded,
              leadingColor: const Color(0xFFE1306C),
              onTap: () => _conversation(context, ref, c),
              trailing: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(when(c['last_message_at'] ?? c['updated_at']),
                      style: TextStyle(fontSize: 11, color: context.mutedColor)),
                  const SizedBox(height: 4),
                  StatusPill(str(c['status'], 'open')),
                ],
              ),
            ),
          ),
          ProviderList(
            provider: igAutomationsProvider,
            emptyLabel: 'No keyword automations',
            emptyIcon: Icons.bolt_rounded,
            tile: (context, a) {
              final active = a['is_active'] == true || a['active'] == true;
              return RecordCard(
                title: str(a['name'] ?? a['keyword'], 'Automation'),
                subtitle:
                    'Keyword: ${str((a['keywords'] as List?)?.join(', ') ?? a['keyword'])} → auto-DM',
                leadingIcon: Icons.bolt_rounded,
                leadingColor: const Color(0xFFE1306C),
                trailing: RowMenu(items: [
                  (
                    active ? 'Pause' : 'Activate',
                    active ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    () async {
                      final ok = await runAction(context,
                          () => Api.post('/instagram/automations/${a['id']}/toggle'),
                          success: 'Updated');
                      if (ok) ref.invalidate(igAutomationsProvider);
                    }
                  ),
                  ('Edit', Icons.edit_rounded,
                      () => _editAutomation(context, ref, a)),
                  (
                    'Delete',
                    Icons.delete_rounded,
                    () async {
                      if (!await confirm(context,
                          title: 'Delete automation?',
                          destructive: true,
                          confirmLabel: 'Delete')) { return; }
                      final ok = await runAction(context,
                          () => Api.delete('/instagram/automations/${a['id']}'),
                          success: 'Deleted');
                      if (ok) ref.invalidate(igAutomationsProvider);
                    }
                  ),
                ]),
              );
            },
          ),
          ProviderList(
            provider: igAccountsProvider,
            emptyLabel: 'No Instagram accounts connected',
            emptyIcon: Icons.photo_camera_rounded,
            tile: (context, a) => RecordCard(
              title: '@${str(a['username'] ?? a['handle'] ?? a['name'], 'account')}',
              subtitle:
                  '${compact(a['followers_count'] ?? a['followers'])} followers · ${str(a['account_type'])}',
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

  Future<void> _conversation(BuildContext context, WidgetRef ref, Rec c) async {
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
            Text('@${str(c['username'] ?? c['name'])}',
                style: Theme.of(ctx)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(str(c['last_message'] ?? c['preview']),
                style: TextStyle(color: ctx.mutedColor)),
            const SizedBox(height: 14),
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
                            data: {'message': controller.text.trim()}),
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

  Future<void> _editAutomation(
      BuildContext context, WidgetRef ref, Rec? existing) async {
    final accounts = await _safeList('/instagram/accounts');
    if (existing == null && accounts.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Connect an Instagram account first.')));
      }
      return;
    }
    final data = <String, dynamic>{};
    if (!context.mounted) return;
    final ok = await showFormSheet(
      context,
      title: existing == null ? 'New automation' : 'Edit automation',
      fields: (ctx) => [
        if (existing == null)
          FSelect<Rec>(
            label: 'Instagram account',
            options: accounts,
            labelOf: (a) => '@${str(a['username'] ?? a['name'])}',
            onSaved: (a) => data['instagram_account_id'] = a?['id'],
          ),
        FText(
          label: 'Name',
          required: true,
          initial: existing?['name'] as String?,
          onSaved: (v) => data['name'] = v,
        ),
        FSelect<String>(
          label: 'Trigger',
          options: const ['comment', 'dm', 'story_reply'],
          initial: (existing?['trigger'] as String?) ?? 'comment',
          onSaved: (v) => data['trigger'] = v ?? 'comment',
        ),
        FChips(
          label: 'Keywords',
          required: true,
          initial: ((existing?['keywords'] as List?) ?? const [])
              .map((e) => '$e')
              .toList(),
          onSaved: (v) => data['keywords'] = v,
        ),
        FSelect<String>(
          label: 'Match type',
          options: const ['any', 'all', 'exact'],
          initial: (existing?['match_type'] as String?) ?? 'any',
          onSaved: (v) => data['match_type'] = v ?? 'any',
        ),
        FText(
          label: 'DM message',
          required: true,
          maxLines: 4,
          initial: existing?['dm_message'] as String?,
          onSaved: (v) => data['dm_message'] = v,
        ),
        FText(
          label: 'Public reply (optional)',
          maxLines: 2,
          initial: existing?['public_reply'] as String?,
          onSaved: (v) => data['public_reply'] = v.isEmpty ? null : v,
        ),
        FBoolField(
          label: 'Hand off to AI agent',
          initial: existing?['handoff_to_ai'] == true,
          onSaved: (v) => data['handoff_to_ai'] = v,
        ),
        FBoolField(
          label: 'Reply once per user',
          initial: existing?['reply_once_per_user'] != false,
          onSaved: (v) => data['reply_once_per_user'] = v,
        ),
        FBoolField(
          label: 'Active',
          initial: existing?['is_active'] != false,
          onSaved: (v) => data['is_active'] = v,
        ),
      ],
      onSubmit: () => existing == null
          ? Api.post('/instagram/automations', data: data)
          : Api.put('/instagram/automations/${existing['id']}',
              data: data..remove('instagram_account_id')),
    );
    if (ok) ref.invalidate(igAutomationsProvider);
  }
}

// ══════════════════════════ WA Agent ══════════════════════════

class WaAgentPage extends ConsumerWidget {
  const WaAgentPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('WA Agent'),
          bottom: const TabBar(tabs: [
            Tab(text: 'Stats'),
            Tab(text: 'Sessions'),
            Tab(text: 'Playbook'),
          ]),
        ),
        body: TabBarView(children: [
          ProviderObject(
            provider: waAgentStatsProvider,
            builder: (context, d) {
              final items = <(String, String, IconData)>[
                ('Conversations', compact(d['conversations'] ?? d['total_sessions']), Icons.forum_rounded),
                ('Handled by AI', compact(d['ai_handled'] ?? d['auto_resolved']), Icons.smart_toy_rounded),
                ('Handed off', compact(d['handed_off'] ?? d['transferred']), Icons.swap_horiz_rounded),
                ('Leads created', compact(d['leads'] ?? d['leads_created']), Icons.trending_up_rounded),
                ('Avg reply', str(d['avg_response_time'] ?? d['avg_reply'], '—'), Icons.timer_outlined),
                ('Satisfaction', '${d['satisfaction'] ?? d['csat'] ?? 0}%', Icons.sentiment_satisfied_rounded),
              ];
              return ListView(children: [StatGrid(items)]);
            },
          ),
          ProviderList(
            provider: waAgentSessionsProvider,
            emptyLabel: 'No agent sessions',
            tile: (context, s) => RecordCard(
              title: str(s['contact_name'] ?? s['contact'] ?? s['phone'], 'Session'),
              subtitle:
                  '${str(s['last_message'] ?? s['summary'])} · ${when(s['updated_at'] ?? s['last_activity_at'])}',
              leadingIcon: Icons.smart_toy_rounded,
              leadingColor: const Color(0xFF14B8A6),
              trailing: RowMenu(items: [
                (
                  'Close',
                  Icons.check_rounded,
                  () async {
                    final ok = await runAction(context,
                        () => Api.post('/wa-agent/sessions/${s['id']}/close'),
                        success: 'Closed');
                    if (ok) ref.invalidate(waAgentSessionsProvider);
                  }
                ),
              ]),
            ),
          ),
          ProviderList(
            provider: waAgentPlaybookProvider,
            emptyLabel: 'No playbook entries',
            emptyIcon: Icons.menu_book_rounded,
            tile: (context, p) => RecordCard(
              title: str(p['name'] ?? p['title'] ?? p['category'], 'Playbook'),
              subtitle: str(p['description'] ?? p['instructions'] ?? p['goal']),
              leadingIcon: Icons.auto_stories_rounded,
              leadingColor: const Color(0xFF14B8A6),
              trailing: RowMenu(items: [
                (
                  (p['is_active'] == true) ? 'Disable' : 'Enable',
                  Icons.toggle_on_rounded,
                  () async {
                    final ok = await runAction(context,
                        () => Api.post('/wa-agent/playbook/${p['id']}/toggle'),
                        success: 'Updated');
                    if (ok) ref.invalidate(waAgentPlaybookProvider);
                  }
                ),
                (
                  'Delete',
                  Icons.delete_rounded,
                  () async {
                    if (!await confirm(context,
                        title: 'Delete entry?',
                        destructive: true,
                        confirmLabel: 'Delete')) { return; }
                    final ok = await runAction(context,
                        () => Api.delete('/wa-agent/playbook/${p['id']}'),
                        success: 'Deleted');
                    if (ok) ref.invalidate(waAgentPlaybookProvider);
                  }
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

// ══════════════════════════ Chat Widget ══════════════════════════

class WidgetPage extends ConsumerWidget {
  const WidgetPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Website Chat Widget')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context, ref, null),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New widget'),
      ),
      body: ProviderList(
        provider: chatWidgetsProvider,
        emptyLabel: 'No widgets configured',
        emptyIcon: Icons.chat_bubble_rounded,
        tile: (context, w) => RecordCard(
          title: str(w['name'] ?? w['title'], 'Widget'),
          subtitle:
              '${str((w['allowed_origins'] as List?)?.join(', ') ?? w['domain'] ?? w['website'])} · key ${str(w['key'] ?? w['widget_key'])}',
          leadingIcon: Icons.chat_bubble_rounded,
          leadingColor: const Color(0xFF6366F1),
          onTap: () => _edit(context, ref, w),
          trailing: RowMenu(items: [
            ('Edit', Icons.edit_rounded, () => _edit(context, ref, w)),
            (
              'Delete',
              Icons.delete_rounded,
              () async {
                if (!await confirm(context,
                    title: 'Delete widget?',
                    destructive: true,
                    confirmLabel: 'Delete')) { return; }
                final ok = await runAction(context,
                    () => Api.delete('/widgets/${w['id']}'),
                    success: 'Deleted');
                if (ok) ref.invalidate(chatWidgetsProvider);
              }
            ),
          ]),
          footer: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '<script src=".../public/widget/${str(w['key'] ?? w['widget_key'], 'KEY')}.js"></script>',
              style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: context.mutedColor),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, Rec? w) async {
    final data = <String, dynamic>{};
    final ok = await showFormSheet(
      context,
      title: w == null ? 'New widget' : 'Edit widget',
      fields: (ctx) => [
        FText(
          label: 'Name',
          required: true,
          initial: w?['name'] as String?,
          onSaved: (v) => data['name'] = v,
        ),
        FText(
          label: 'Agent name',
          initial: w?['agent_name'] as String?,
          onSaved: (v) => v.isEmpty ? null : data['agent_name'] = v,
        ),
        FText(
          label: 'Greeting',
          maxLines: 3,
          initial: w?['greeting'] as String?,
          onSaved: (v) => v.isEmpty ? null : data['greeting'] = v,
        ),
        FChips(
          label: 'Allowed website domains',
          hint: 'example.com, shop.example.com',
          initial: ((w?['allowed_origins'] as List?) ?? const [])
              .map((e) => '$e')
              .toList(),
          onSaved: (v) => data['allowed_origins'] = v,
        ),
        FChips(
          label: 'Notify emails',
          initial: ((w?['notify_emails'] as List?) ?? const [])
              .map((e) => '$e')
              .toList(),
          onSaved: (v) => data['notify_emails'] = v,
        ),
        FBoolField(
          label: 'Active',
          initial: w?['is_active'] != false,
          onSaved: (v) => data['is_active'] = v,
        ),
      ],
      onSubmit: () => w == null
          ? Api.post('/widgets', data: data)
          : Api.put('/widgets/${w['id']}', data: data),
    );
    if (ok) ref.invalidate(chatWidgetsProvider);
  }
}

// ══════════════════════════ Knowledge Base ══════════════════════════

class KnowledgeBasePage extends ConsumerWidget {
  const KnowledgeBasePage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Knowledge Base')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _add(context, ref),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add content'),
      ),
      body: ProviderList(
        provider: knowledgeBaseProvider,
        emptyLabel: 'No documents added',
        emptyIcon: Icons.menu_book_rounded,
        tile: (context, k) => RecordCard(
          title: str(k['name'] ?? k['title'] ?? k['filename'], 'Document'),
          subtitle:
              '${str(k['document_type'] ?? k['type'])} · ${when(k['created_at'])}',
          leadingIcon: switch ('${k['document_type'] ?? k['type'] ?? ''}'.toLowerCase()) {
            final t when t.contains('url') => Icons.link_rounded,
            final t when t.contains('file') => Icons.description_rounded,
            _ => Icons.article_rounded,
          },
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              StatusPill(str(k['status'], 'ready')),
              RowMenu(items: [
                (
                  'Reprocess',
                  Icons.sync_rounded,
                  () async {
                    final ok = await runAction(context,
                        () => Api.post('/wa-agent/knowledge-base/${k['id']}/reprocess'),
                        success: 'Reprocessing');
                    if (ok) ref.invalidate(knowledgeBaseProvider);
                  }
                ),
                (
                  'Delete',
                  Icons.delete_rounded,
                  () async {
                    if (!await confirm(context,
                        title: 'Delete document?',
                        destructive: true,
                        confirmLabel: 'Delete')) { return; }
                    final ok = await runAction(context,
                        () => Api.delete('/wa-agent/knowledge-base/${k['id']}'),
                        success: 'Deleted');
                    if (ok) ref.invalidate(knowledgeBaseProvider);
                  }
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final data = <String, dynamic>{'document_type': 'text'};
    String type = 'text';
    final ok = await showFormSheet(
      context,
      title: 'Add knowledge',
      submitLabel: 'Add',
      fields: (ctx) => [
        FText(
          label: 'Name',
          required: true,
          onSaved: (v) => data['name'] = v,
        ),
        FSelect<String>(
          label: 'Type',
          options: const ['text', 'url'],
          initial: 'text',
          onSaved: (v) {
            type = v ?? 'text';
            data['document_type'] = type;
          },
        ),
        FText(
          label: 'Text content',
          hint: 'Used when type = text',
          maxLines: 6,
          onSaved: (v) => v.isEmpty ? null : data['raw_content'] = v,
        ),
        FText(
          label: 'Source URL',
          hint: 'Used when type = url',
          keyboardType: TextInputType.url,
          onSaved: (v) => v.isEmpty ? null : data['source_url'] = v,
        ),
        FText(
          label: 'Description (optional)',
          maxLines: 2,
          onSaved: (v) => v.isEmpty ? null : data['description'] = v,
        ),
      ],
      onSubmit: () => Api.post('/wa-agent/knowledge-base', data: data),
    );
    if (ok) ref.invalidate(knowledgeBaseProvider);
  }
}

// ══════════════════════════ Listings ══════════════════════════

class ListingsPage extends ConsumerWidget {
  const ListingsPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Listings & Products')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context, ref, null),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New listing'),
      ),
      body: ProviderList(
        provider: listingsProvider,
        emptyLabel: 'No listings yet',
        emptyIcon: Icons.inventory_2_rounded,
        tile: (context, l) => RecordCard(
          title: str(l['title'] ?? l['name']),
          subtitle: str(l['description'] ?? l['location']),
          leadingIcon: Icons.inventory_2_rounded,
          leadingColor: const Color(0xFFEA580C),
          onTap: () => _edit(context, ref, l),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (l['price'] != null)
                Text(money(l['price']),
                    style: const TextStyle(fontWeight: FontWeight.w800)),
              RowMenu(items: [
                ('Edit', Icons.edit_rounded, () => _edit(context, ref, l)),
                (
                  'Delete',
                  Icons.delete_rounded,
                  () async {
                    if (!await confirm(context,
                        title: 'Delete listing?',
                        destructive: true,
                        confirmLabel: 'Delete')) { return; }
                    final ok = await runAction(context,
                        () => Api.delete('/listings/${l['id']}'),
                        success: 'Deleted');
                    if (ok) ref.invalidate(listingsProvider);
                  }
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, Rec? l) async {
    final data = <String, dynamic>{};
    final ok = await showFormSheet(
      context,
      title: l == null ? 'New listing' : 'Edit listing',
      fields: (ctx) => [
        FText(
          label: 'Type',
          hint: 'e.g. property, course, service, product',
          required: l == null,
          initial: l?['type'] as String?,
          onSaved: (v) => v.isEmpty ? null : data['type'] = v,
        ),
        FText(
          label: 'Title',
          required: l == null,
          initial: l?['title'] as String?,
          onSaved: (v) => v.isEmpty ? null : data['title'] = v,
        ),
        FText(
          label: 'Description',
          maxLines: 4,
          initial: l?['description'] as String?,
          onSaved: (v) => v.isEmpty ? null : data['description'] = v,
        ),
        FSelect<String>(
          label: 'Status',
          options: const ['draft', 'active', 'inactive', 'sold'],
          initial: (l?['status'] as String?) ?? 'active',
          onSaved: (v) => data['status'] = v ?? 'active',
        ),
        FNumber(
          label: 'Price',
          initial: num.tryParse('${l?['price'] ?? ''}'),
          onSaved: (v) => v == null ? null : data['price'] = v,
        ),
        FText(
          label: 'Price unit',
          hint: 'e.g. /month, one-time',
          initial: l?['price_unit'] as String?,
          onSaved: (v) => v.isEmpty ? null : data['price_unit'] = v,
        ),
        FText(
          label: 'Location',
          initial: l?['location'] as String?,
          onSaved: (v) => v.isEmpty ? null : data['location'] = v,
        ),
      ],
      onSubmit: () => l == null
          ? Api.post('/listings', data: data)
          : Api.put('/listings/${l['id']}', data: data),
    );
    if (ok) ref.invalidate(listingsProvider);
  }
}

// ── helpers ─────────────────────────────────────────────────────────────
Future<List<Rec>> _safeList(String path) async {
  try {
    return await Api.list(path);
  } catch (_) {
    return const [];
  }
}
