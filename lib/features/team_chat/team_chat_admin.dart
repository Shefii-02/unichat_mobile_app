import 'package:unichat_mobile_app/features/team_chat/delete_group_dialog.dart';
import 'package:flutter/material.dart';
import 'package:unichat_mobile_app/core/network/api.dart';
import 'package:unichat_mobile_app/core/theme/app_theme.dart';
import 'package:unichat_mobile_app/features/team_chat/team_chat_data.dart';
import 'package:unichat_mobile_app/features/team_chat/team_chats_page.dart';

/// Company moderation for team chat (owner / staff managers): review reported messages and manage every
/// group in the company — including groups the admin is not in and people who have left.
class TeamChatModerationPage extends StatefulWidget {
  const TeamChatModerationPage({super.key});
  @override
  State<TeamChatModerationPage> createState() => _TeamChatModerationPageState();
}

class _TeamChatModerationPageState extends State<TeamChatModerationPage> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Chat moderation'),
          bottom: TabBar(controller: _tabs, tabs: const [Tab(text: 'Reports'), Tab(text: 'Groups')]),
        ),
        body: TabBarView(controller: _tabs, children: const [_ReportsTab(), _GroupsTab()]),
      );
}

const _reasonLabels = {'spam': 'Spam', 'harassment': 'Harassment', 'inappropriate': 'Inappropriate', 'other': 'Other'};

class _ReportsTab extends StatefulWidget {
  const _ReportsTab();
  @override
  State<_ReportsTab> createState() => _ReportsTabState();
}

class _ReportsTabState extends State<_ReportsTab> {
  String _status = 'open';
  late Future<List<Map<String, dynamic>>> _f = _load();

  Future<List<Map<String, dynamic>>> _load() => Api.list('/team-chat/admin/reports', query: {'status': _status});
  void _reload() => setState(() => _f = _load());

  Future<void> _resolve(Map r) async {
    final isGroup = r['chat_type'] == 'group';
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.check_circle_outline_rounded), title: const Text('Dismiss report'), subtitle: const Text('No action needed'), onTap: () => Navigator.pop(context, 'dismiss')),
          ListTile(leading: const Icon(Icons.delete_outline_rounded, color: Colors.red), title: const Text('Delete message'), onTap: () => Navigator.pop(context, 'delete_message')),
          if (isGroup) ...[
            ListTile(leading: const Icon(Icons.person_remove_rounded, color: Colors.red), title: Text('Remove ${r['sender_name'] ?? 'sender'} from group'), onTap: () => Navigator.pop(context, 'remove_sender')),
            ListTile(leading: const Icon(Icons.gavel_rounded, color: Colors.red), title: const Text('Delete message and remove sender'), onTap: () => Navigator.pop(context, 'delete_and_remove')),
          ],
        ]),
      ),
    );
    if (action == null) return;
    try {
      await Api.post('/team-chat/admin/reports/${r['id']}/resolve', data: {'action': action});
      _reload();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
    }
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          child: Row(children: [
            for (final s in const [('open', 'Open'), ('actioned', 'Actioned'), ('dismissed', 'Dismissed'), ('all', 'All')])
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ChoiceChip(label: Text(s.$2), selected: _status == s.$1, onSelected: (_) { _status = s.$1; _reload(); }),
              ),
          ]),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async { _reload(); await _f; },
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _f,
              builder: (_, s) {
                if (s.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
                if (s.hasError) return ListView(children: [Padding(padding: const EdgeInsets.all(32), child: Text(apiErrorMessage(s.error!), textAlign: TextAlign.center))]);
                final rows = s.data ?? const [];
                if (rows.isEmpty) {
                  return ListView(children: [
                    const SizedBox(height: 90),
                    Icon(Icons.verified_user_outlined, size: 56, color: context.mutedColor),
                    const SizedBox(height: 12),
                    Center(child: Text('No reports here', style: TextStyle(color: context.mutedColor))),
                  ]);
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: rows.length,
                  itemBuilder: (_, i) => _card(context, rows[i]),
                );
              },
            ),
          ),
        ),
      ]);

  Widget _card(BuildContext context, Map r) {
    final snap = r['snapshot'] is Map ? r['snapshot'] as Map : const {};
    final open = r['status'] == 'open';
    final text = snap['body'] ?? (snap['attachment_name'] != null ? '📎 ${snap['attachment_name']}' : '${snap['type'] ?? ''}');
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: context.lineColor)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            decoration: BoxDecoration(color: Colors.red.withOpacity(0.12), borderRadius: BorderRadius.circular(99)),
            child: Text(_reasonLabels[r['reason']] ?? '${r['reason']}', style: const TextStyle(color: Colors.red, fontSize: 11.5, fontWeight: FontWeight.w700)),
          ),
          const Spacer(),
          Text('${teamDay(r['created_at'])} ${teamTime(r['created_at'])}', style: TextStyle(fontSize: 11, color: context.mutedColor)),
        ]),
        const SizedBox(height: 8),
        Text('${r['sender_name'] ?? 'Unknown'} in ${r['chat_name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: context.lineColor.withOpacity(0.35), borderRadius: BorderRadius.circular(10)),
          child: Text('$text', maxLines: 6, overflow: TextOverflow.ellipsis),
        ),
        if (r['note'] != null && '${r['note']}'.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text('Note: ${r['note']}', style: TextStyle(fontSize: 12.5, color: context.mutedColor)),
        ],
        const SizedBox(height: 6),
        Text('Reported by ${r['reporter_name'] ?? 'someone'}', style: TextStyle(fontSize: 12, color: context.mutedColor)),
        const SizedBox(height: 8),
        Row(children: [
          if (open)
            FilledButton.tonal(onPressed: () => _resolve(r), child: const Text('Take action'))
          else
            Text('${r['status'] == 'dismissed' ? 'Dismissed' : 'Actioned'}${r['action'] != null && r['status'] != 'dismissed' ? ' · ${'${r['action']}'.replaceAll('_', ' ')}' : ''}',
                style: TextStyle(color: context.mutedColor, fontWeight: FontWeight.w600)),
        ]),
      ]),
    );
  }
}

class _GroupsTab extends StatefulWidget {
  const _GroupsTab();
  @override
  State<_GroupsTab> createState() => _GroupsTabState();
}

class _GroupsTabState extends State<_GroupsTab> {
  late Future<List<Map<String, dynamic>>> _f = Api.list('/team-chat/admin/groups');
  void _reload() => setState(() => _f = Api.list('/team-chat/admin/groups'));

  @override
  Widget build(BuildContext context) => RefreshIndicator(
        onRefresh: () async { _reload(); await _f; },
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _f,
          builder: (_, s) {
            if (s.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
            if (s.hasError) return ListView(children: [Padding(padding: const EdgeInsets.all(32), child: Text(apiErrorMessage(s.error!), textAlign: TextAlign.center))]);
            final rows = s.data ?? const [];
            if (rows.isEmpty) return ListView(children: [const SizedBox(height: 90), Center(child: Text('No groups yet', style: TextStyle(color: context.mutedColor)))]);
            return ListView.separated(
              itemCount: rows.length,
              separatorBuilder: (_, __) => Divider(height: 1, indent: 72, color: context.lineColor),
              itemBuilder: (_, i) {
                final g = rows[i];
                final reports = (g['open_reports'] as num?)?.toInt() ?? 0;
                return ListTile(
                  leading: ChatAvatar(name: '${g['name']}', group: true, url: g['avatar'] as String?),
                  title: Text('${g['name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text('${g['members']} members${(g['former_members'] as num) > 0 ? ' · ${g['former_members']} left' : ''} · by ${g['creator'] ?? '—'}'),
                  trailing: reports > 0
                      ? Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(color: Colors.red.withOpacity(0.12), borderRadius: BorderRadius.circular(99)),
                          child: Text('$reports report${reports > 1 ? 's' : ''}', style: const TextStyle(color: Colors.red, fontSize: 11.5, fontWeight: FontWeight.w700)),
                        )
                      : const Icon(Icons.chevron_right_rounded),
                  onTap: () async {
                    final changed = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => AdminGroupPage(groupId: (g['id'] as num).toInt())));
                    if (changed == true) _reload();
                  },
                );
              },
            );
          },
        ),
      );
}

/// A group seen as a company admin: current members, people who left, remove / delete.
class AdminGroupPage extends StatefulWidget {
  const AdminGroupPage({super.key, required this.groupId});
  final int groupId;
  @override
  State<AdminGroupPage> createState() => _AdminGroupPageState();
}

class _AdminGroupPageState extends State<AdminGroupPage> {
  Map<String, dynamic>? _d;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await Api.one('/team-chat/admin/groups/${widget.groupId}');
      if (mounted) setState(() => _d = d);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
    }
  }

  Future<bool> _confirm(String title, String body, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(action)),
          ],
        ),
      ) ??
      false;

  @override
  Widget build(BuildContext context) {
    final d = _d;
    if (d == null) return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    final members = (d['members'] as List).whereType<Map>().toList();
    final former = (d['former_members'] as List).whereType<Map>().toList();
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {},
      child: Scaffold(
        appBar: AppBar(
          title: Text('${d['name']}'),
          leading: BackButton(onPressed: () => Navigator.pop(context, _changed)),
          actions: [
            if (canDeleteChats)
            IconButton(
              icon: const Icon(Icons.delete_forever_rounded, color: Colors.red),
              onPressed: () async {
                final withMedia = await askDeleteGroup(context, '${d['name']}');
                if (withMedia != null) {
                  try {
                    await Api.delete('/team-chat/admin/groups/${widget.groupId}?delete_media=${withMedia ? 1 : 0}');
                    if (mounted) Navigator.pop(context, true);
                  } catch (e) {
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
                  }
                }
              },
            ),
          ],
        ),
        body: ListView(children: [
          Padding(padding: const EdgeInsets.fromLTRB(16, 14, 16, 4), child: Text('MEMBERS (${members.length})', style: TextStyle(color: context.mutedColor, fontWeight: FontWeight.w800, fontSize: 12, letterSpacing: 0.6))),
          for (final m in members)
            ListTile(
              leading: ChatAvatar(name: '${m['name']}', url: m['avatar'] as String?),
              title: Text('${m['name']}', style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: m['role'] == 'admin' ? const Text('Group admin') : null,
              trailing: IconButton(
                icon: const Icon(Icons.person_remove_rounded, color: Colors.red),
                onPressed: () async {
                  if (await _confirm('Remove member', 'Remove ${m['name']} from this group?', 'Remove')) {
                    try {
                      await Api.delete('/team-chat/admin/groups/${widget.groupId}/members/${m['id']}');
                      _changed = true;
                      _load();
                    } catch (e) {
                      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
                    }
                  }
                },
              ),
            ),
          if (former.isNotEmpty) ...[
            const Divider(),
            Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 4), child: Text('LEFT / REMOVED (${former.length})', style: TextStyle(color: context.mutedColor, fontWeight: FontWeight.w800, fontSize: 12, letterSpacing: 0.6))),
            for (final m in former)
              ListTile(
                leading: ChatAvatar(name: '${m['name']}', url: m['avatar'] as String?),
                title: Text('${m['name']}', style: TextStyle(color: context.mutedColor)),
                subtitle: Text('Left ${teamDay(m['left_at'])}'),
              ),
          ],
          const SizedBox(height: 24),
        ]),
      ),
    );
  }
}
