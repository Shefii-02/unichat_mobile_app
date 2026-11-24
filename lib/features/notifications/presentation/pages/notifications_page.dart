import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:unichat_mobile_app/core/constants/app_colors.dart';
import 'package:unichat_mobile_app/core/network/api.dart';
import 'package:unichat_mobile_app/core/utils/format_utils.dart';
import 'package:unichat_mobile_app/features/notifications/notification_providers.dart';

/// This person's own notification inbox — leads first, everything else under "Other" — with the team-chat unread count on top.
/// Backed by GET /notifications (scoped to the signed-in account) and POST /notifications/read.
class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});
  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String _tab = 'all'; // all | lead | other
  int _unread = 0, _unreadLeads = 0, _unreadOther = 0, _team = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await Api.raw.get('/notifications', queryParameters: {'category': _tab, 'per_page': 50});
      final d = res.data as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _items = ((d['data'] as List?) ?? const []).whereType<Map<String, dynamic>>().toList();
        _unread = (d['unread'] as num?)?.toInt() ?? 0;
        _unreadLeads = (d['unread_leads'] as num?)?.toInt() ?? 0;
        _unreadOther = (d['unread_other'] as num?)?.toInt() ?? 0;
        _team = (d['team_chat_unread'] as num?)?.toInt() ?? 0;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() { _items = []; _loading = false; });
    }
  }

  void _refreshBadge() => ProviderScope.containerOf(context, listen: false).invalidate(notificationBadgeProvider);

  Future<void> _markAll() async {
    try {
      await Api.post('/notifications/read', data: {});
      _refreshBadge();
      await _load();
    } catch (_) {}
  }

  Future<void> _open(Map<String, dynamic> n) async {
    final id = (n['id'] as num?)?.toInt();
    if (n['read_at'] == null && id != null) {
      Api.post('/notifications/read', data: {'ids': [id]}).then((_) { _refreshBadge(); }).catchError((_) {});
      setState(() => n['read_at'] = DateTime.now().toIso8601String());
    }
    final d = (n['data'] as Map?) ?? const {};
    switch ('${d['action']}') {
      case 'open_lead':
        final lead = int.tryParse('${d['lead_id']}');
        if (lead != null) context.push('/lead-detail/$lead');
      case 'open_team_chat':
        final chat = int.tryParse('${d['chat_id']}');
        if (chat != null) context.push('/team-chat/$chat');
      case 'open_leads' || 'lead_offer' || 'ai_handoff_offer':
        context.go('/leads');
    }
  }

  String _icon(String c) => switch (c) {
        'lead' => '🎯', 'team' => '💬', 'hr' => '🕒', 'campaign' => '📢', 'billing' => '💳', 'system' => '⚙️', _ => '🔔',
      };

  @override
  Widget build(BuildContext context) {
    Widget chip(String id, String label, int n) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ChoiceChip(
            label: Text(n > 0 ? '$label  $n' : label),
            selected: _tab == id,
            onSelected: (_) { setState(() => _tab = id); _load(); },
          ),
        );
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications'), actions: [
        IconButton(icon: const Icon(Icons.done_all), onPressed: _unread > 0 ? _markAll : null, tooltip: 'Mark all read'),
      ]),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(children: [chip('all', 'All', _unread), chip('lead', 'Leads', _unreadLeads), chip('other', 'Other', _unreadOther)]),
        ),
        if (_team > 0)
          ListTile(
            dense: true,
            leading: const Text('💬', style: TextStyle(fontSize: 22)),
            title: const Text('Team chat'),
            trailing: Text('$_team unread', style: const TextStyle(fontWeight: FontWeight.w700)),
            onTap: () => context.go('/team-chat'),
          ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _items.isEmpty
                  ? const Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text('🔔', style: TextStyle(fontSize: 48)),
                        SizedBox(height: 12),
                        Text('No notifications', style: TextStyle(color: AppColors.textLight, fontSize: 16)),
                      ]),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        itemCount: _items.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final n = _items[i];
                          final read = n['read_at'] != null;
                          final ts = n['created_at'] != null ? DateTime.tryParse('${n['created_at']}') : null;
                          return ListTile(
                            leading: Text(_icon('${n['category']}'), style: const TextStyle(fontSize: 26)),
                            title: Text('${n['title'] ?? ''}', style: TextStyle(fontWeight: read ? FontWeight.normal : FontWeight.w700)),
                            subtitle: Text([if ((n['message'] ?? '').toString().isNotEmpty) '${n['message']}', FormatUtils.relative(ts)].join('\n')),
                            isThreeLine: (n['message'] ?? '').toString().isNotEmpty,
                            tileColor: read ? null : AppColors.primary.withAlpha(8),
                            onTap: () => _open(n),
                          );
                        },
                      ),
                    ),
        ),
      ]),
    );
  }
}
