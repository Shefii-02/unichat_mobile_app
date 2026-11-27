import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:unichat_mobile_app/core/theme/mockup_palette.dart';
import 'package:unichat_mobile_app/core/widgets/app_empty_state.dart';
import 'package:unichat_mobile_app/features/instagram/presentation/pages/instagram_inbox_page.dart';
import 'package:unichat_mobile_app/features/modules/_shared.dart';
import 'package:unichat_mobile_app/features/wa_cloud/presentation/pages/wa_cloud_inbox_page.dart';

/// "My chats" per channel — only the conversations assigned to the signed-in person. Feeds the round icons on the Sales home
/// (WA Cloud, WA Chat, Instagram, Messenger, Web widget): each shows how many are assigned to me; tapping opens the list directly when
/// the channel has one number / account / widget, and a list of them (with each one's count) when it has several.

class ChatChannel {
  const ChatChannel(this.key, this.label, this.total, this.sources);
  final String key;
  final String label;
  final int total;
  final List<ChatSource> sources;
}

class ChatSource {
  const ChatSource(this.id, this.label, this.count);
  final int id;
  final String label;
  final int count;
}

final myChatChannelsProvider = FutureProvider.autoDispose<Map<String, ChatChannel>>((ref) async {
  final res = await Api.raw.get('/chat-channels/mine');
  final out = <String, ChatChannel>{};
  for (final c in ((res.data as Map)['channels'] as List? ?? const []).whereType<Map>()) {
    out['${c['key']}'] = ChatChannel(
      '${c['key']}',
      '${c['label']}',
      (c['total'] as num?)?.toInt() ?? 0,
      [for (final s in (c['sources'] as List? ?? const []).whereType<Map>()) ChatSource((s['id'] as num?)?.toInt() ?? 0, '${s['label']}', (s['count'] as num?)?.toInt() ?? 0)],
    );
  }
  return out;
});

/// Icon / colour per channel.
({IconData icon, Color color}) channelStyle(String key) => switch (key) {
      'wa_cloud' => (icon: Icons.cloud_done_rounded, color: const Color(0xFF16A34A)),
      'wa_chat' => (icon: Icons.chat_rounded, color: const Color(0xFF22C55E)),
      'instagram' => (icon: Icons.camera_alt_rounded, color: const Color(0xFFE1306C)),
      'messenger' => (icon: Icons.messenger_rounded, color: const Color(0xFF0084FF)),
      _ => (icon: Icons.web_rounded, color: const Color(0xFF6366F1)),
    };

/// Tap on a channel's round icon: one source → straight to its chats; several → pick the number / account / widget first.
Future<void> openChannel(BuildContext context, WidgetRef ref, String key) async {
  Map<String, ChatChannel> data;
  try {
    data = await ref.refresh(myChatChannelsProvider.future);
  } catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
    return;
  }
  final ch = data[key];
  if (ch == null || !context.mounted) return;
  if (ch.sources.length > 1) {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => _SourcesPage(channel: ch)));
  } else {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => MyChatsPage(channel: ch, source: ch.sources.isEmpty ? null : ch.sources.first)));
  }
}

/// Several numbers / accounts / widgets: each with how many chats are assigned to me.
class _SourcesPage extends StatelessWidget {
  const _SourcesPage({required this.channel});
  final ChatChannel channel;

  @override
  Widget build(BuildContext context) {
    final st = channelStyle(channel.key);
    return Scaffold(
      appBar: AppBar(title: Text('${channel.label} — ${channel.total} assigned to me')),
      body: ListView.separated(
        itemCount: channel.sources.length,
        separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
        itemBuilder: (_, i) {
          final s = channel.sources[i];
          return ListTile(
            leading: CircleAvatar(backgroundColor: st.color.withValues(alpha: 0.12), child: Icon(st.icon, color: st.color, size: 20)),
            title: Text(s.label, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('${s.count} assigned to me'),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(color: st.color, borderRadius: BorderRadius.circular(12)),
              child: Text('${s.count}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
            ),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => MyChatsPage(channel: channel, source: s))),
          );
        },
      ),
    );
  }
}

/// The chats assigned to me on one channel (and, when it has several, one number / account / widget).
class MyChatsPage extends ConsumerStatefulWidget {
  const MyChatsPage({super.key, required this.channel, this.source});
  final ChatChannel channel;
  final ChatSource? source;
  @override
  ConsumerState<MyChatsPage> createState() => _MyChatsPageState();
}

class _MyChatsPageState extends ConsumerState<MyChatsPage> {
  List<Map<String, dynamic>>? _rows;
  String? _error;
  final _search = TextEditingController();

  String get _key => widget.channel.key;
  int? get _sid => widget.source?.id;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _maps(dynamic v) => (v as List? ?? const []).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();

  Future<void> _load() async {
    final q = _search.text.trim();
    try {
      List<Map<String, dynamic>> rows;
      switch (_key) {
        case 'wa_cloud':
          final r = await Api.raw.get('/conversations', queryParameters: {'mine': 1, 'per_page': 100, if (_sid != null && _sid! > 0) 'wa_phone_number_id': _sid, if (q.isNotEmpty) 'search': q});
          rows = _maps((r.data as Map)['conversations']);
        case 'wa_chat':
          final r = await Api.raw.get('/chat-channels/wa-chat', queryParameters: {if (_sid != null) 'session': _sid, if (q.isNotEmpty) 'q': q});
          rows = _maps((r.data as Map)['data']);
        case 'instagram' || 'messenger':
          final r = await Api.raw.get('/instagram/conversations', queryParameters: {'mine': 1, 'channel': _key == 'messenger' ? 'facebook' : 'instagram', if (_sid != null && _sid! > 0) 'account_id': _sid});
          rows = _maps((r.data as Map)['data']);
        default:
          if (_sid == null) {
            rows = [];
          } else {
            final r = await Api.raw.get('/widgets/$_sid/conversations', queryParameters: {'mine': 1});
            rows = _maps((r.data as Map)['data']);
          }
      }
      if (q.isNotEmpty && (_key == 'instagram' || _key == 'messenger' || _key == 'widget')) {
        final t = q.toLowerCase();
        rows = rows.where((r) => '${r['participant_username'] ?? ''}${r['visitor_name'] ?? ''}${r['visitor_phone'] ?? ''}'.toLowerCase().contains(t)).toList();
      }
      if (mounted) setState(() { _rows = rows; _error = null; });
    } catch (e) {
      if (mounted) setState(() => _error = apiErrorMessage(e));
    }
  }

  ({String title, String sub, int unread, String at}) _fields(Map<String, dynamic> r) {
    switch (_key) {
      case 'wa_cloud':
        final last = r['last_message'] is Map ? (r['last_message'] as Map).cast<String, dynamic>() : const <String, dynamic>{};
        return (
          title: str(r['contact_name']).isNotEmpty ? str(r['contact_name']) : (r['contact'] is Map ? str((r['contact'] as Map)['name']) : '').isNotEmpty ? str((r['contact'] as Map)['name']) : str(r['phone']),
          sub: str(last['body'] ?? last['content'] ?? last['text'] ?? r['phone']),
          unread: (r['unread_count'] as num?)?.toInt() ?? 0,
          at: when(r['last_message_at']),
        );
      case 'wa_chat':
        return (title: str(r['name']), sub: '${str(r['phone'])} · ${str(r['stage']).replaceAll('_', ' ')}', unread: 0, at: when(r['updated_at']));
      case 'instagram' || 'messenger':
        return (title: str(r['participant_username'] ?? r['participant_id'], 'Conversation'), sub: str(r['last_message_preview']), unread: (r['unread_count'] as num?)?.toInt() ?? 0, at: when(r['last_message_at']));
      default:
        final who = str(r['visitor_name']).isNotEmpty ? str(r['visitor_name']) : str(r['visitor_phone'] ?? r['visitor_email'], 'Visitor');
        return (title: who, sub: [str(r['visitor_phone']), str(r['visitor_email']), str(r['status'])].where((e) => e.isNotEmpty).join(' · '), unread: 0, at: when(r['last_message_at']));
    }
  }

  void _open(Map<String, dynamic> r) {
    switch (_key) {
      case 'wa_cloud':
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => WaCloudThreadPage(conversation: r)));
      case 'wa_chat':
        context.push('/lead-detail/${r['id']}');
      case 'instagram' || 'messenger':
        const InstagramInboxPage().openConversation(context, ref, r);
      default:
        final lead = r['lead_id'] ?? (r['lead'] is Map ? (r['lead'] as Map)['id'] : null);
        if (lead != null) context.push('/lead-detail/$lead');
    }
  }

  @override
  Widget build(BuildContext context) {
    final st = channelStyle(_key);
    final title = widget.source == null || widget.channel.sources.length <= 1 ? widget.channel.label : '${widget.channel.label} · ${widget.source!.label}';
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: TextField(
            controller: _search,
            decoration: const InputDecoration(hintText: 'Search name or number…', prefixIcon: Icon(Icons.search), isDense: true),
            onSubmitted: (_) => _load(),
            onChanged: (v) { if (v.isEmpty) _load(); },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
          child: Align(alignment: Alignment.centerLeft, child: Text('Only chats assigned to me', style: TextStyle(fontSize: 11.5, color: context.mutedColor))),
        ),
        Expanded(
          child: _error != null
              ? Center(child: Text(_error!))
              : _rows == null
                  ? const Center(child: CircularProgressIndicator())
                  : _rows!.isEmpty
                      ? const AppEmptyState(icon: Icons.forum_outlined, title: 'No chats', subtitle: 'Nothing is assigned to you here.')
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView.separated(
                            itemCount: _rows!.length,
                            separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
                            itemBuilder: (_, i) {
                              final f = _fields(_rows![i]);
                              return ListTile(
                                onTap: () => _open(_rows![i]),
                                leading: CircleAvatar(backgroundColor: st.color.withValues(alpha: 0.12), child: Icon(st.icon, color: st.color, size: 20)),
                                title: Text(f.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                                subtitle: Text(f.sub, maxLines: 1, overflow: TextOverflow.ellipsis),
                                trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                                  Text(f.at, style: TextStyle(fontSize: 11, color: context.mutedColor)),
                                  if (f.unread > 0)
                                    Container(
                                      margin: const EdgeInsets.only(top: 4),
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                      decoration: BoxDecoration(color: st.color, borderRadius: BorderRadius.circular(10)),
                                      child: Text('${f.unread}', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
                                    ),
                                ]),
                              );
                            },
                          ),
                        ),
        ),
      ]),
    );
  }
}
