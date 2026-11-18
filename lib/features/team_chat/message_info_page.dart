import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:unichat_mobile_app/core/network/api.dart';
import 'package:unichat_mobile_app/features/team_chat/team_chat_data.dart';
import 'package:unichat_mobile_app/features/team_chat/team_chat_style.dart';
import 'package:unichat_mobile_app/features/team_chat/team_chats_page.dart';
import 'package:unichat_mobile_app/features/team_chat/team_media.dart';

String _stamp(Object? iso) {
  if (iso == null) return '—';
  return '${teamDay(iso)}, ${teamTime(iso)}';
}

/// Message info — who it was delivered to and who has read it, with times. Only the sender and company
/// admins can open it (the server enforces this too). Works the same for direct chats and groups.
class MessageInfoPage extends StatelessWidget {
  const MessageInfoPage({super.key, required this.messageId, required this.preview});
  final int messageId;
  final String preview;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.transparent,
        extendBodyBehindAppBar: true,
        appBar: const GlassAppBar(title: Text('Message info')),
        body: GlassBackground(
          child: SafeArea(
            child: FutureBuilder<Map<String, dynamic>>(
              future: Api.one('/team-chat/messages/$messageId/info'),
              builder: (_, s) {
                if (s.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
                if (s.hasError) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(apiErrorMessage(s.error!), textAlign: TextAlign.center)));
                final d = s.data!;
                final rec = (d['recipients'] as List? ?? const []).whereType<Map>().toList();
                final read = rec.where((r) => r['read'] == true).toList();
                final delivered = rec.where((r) => r['delivered'] == true && r['read'] != true).toList();
                final pending = rec.where((r) => r['delivered'] != true).toList();
                return ListView(physics: teamScrollPhysics, padding: const EdgeInsets.fromLTRB(16, 12, 16, 32), children: [
                  GlassCard(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(preview, maxLines: 4, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15, color: Glass.text(context))),
                      const SizedBox(height: 8),
                      Text('Sent ${_stamp(d['sent_at'])}${d['sender_name'] != null ? ' by ${d['sender_name']}' : ''}', style: TextStyle(fontSize: 12.5, color: Glass.muted(context))),
                    ]),
                  ),
                  const SizedBox(height: 14),
                  _section(context, 'Read by', Icons.done_all_rounded, Glass.accent, read, (r) => _stamp(r['read_at'])),
                  _section(context, 'Delivered to', Icons.done_all_rounded, Glass.muted(context), delivered, (r) => _stamp(r['delivered_at'])),
                  _section(context, 'Not delivered yet', Icons.schedule_rounded, Glass.muted(context), pending, (_) => 'Waiting for their device'),
                ]);
              },
            ),
          ),
        ),
      );

  Widget _section(BuildContext context, String title, IconData icon, Color color, List<Map> rows, String Function(Map) when) {
    if (rows.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
            child: Row(children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Text('$title · ${rows.length}', style: TextStyle(fontWeight: FontWeight.w800, color: Glass.text(context))),
            ]),
          ),
          for (final r in rows)
            ListTile(
              dense: true,
              leading: ChatAvatar(name: '${r['name']}', url: r['avatar'] as String?, radius: 17),
              title: Text('${r['name']}', style: TextStyle(fontWeight: FontWeight.w700, color: Glass.text(context))),
              trailing: Text(when(r), style: TextStyle(fontSize: 11.5, color: Glass.muted(context))),
            ),
        ]),
      ),
    );
  }
}

/// What a deleted-for-everyone message said — company admins only (the server checks).
Future<void> showOriginalMessage(BuildContext context, int messageId) async {
  Map<String, dynamic> d;
  try {
    d = await Api.one('/team-chat/messages/$messageId/original');
  } catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
    return;
  }
  if (!context.mounted) return;
  final type = '${d['type']}';
  final text = d['body'] ??
      (type == 'location' ? '📍 ${d['location_label'] ?? 'Location'} (${d['latitude']}, ${d['longitude']})' : null) ??
      (type == 'contact' ? '👤 ${d['contact_name']} ${d['contact_phone'] ?? ''}' : null) ??
      (d['attachment_name'] != null ? '📎 ${d['attachment_name']}' : type);
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => Padding(
      padding: const EdgeInsets.all(12),
      child: GlassCard(
        opacity: 0.9,
        radius: 24,
        padding: const EdgeInsets.all(18),
        child: SafeArea(
          top: false,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.visibility_rounded, color: Glass.accentDeep),
              const SizedBox(width: 8),
              Text('Deleted message (admin view)', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5, color: Glass.text(context))),
            ]),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Glass.accent.withOpacity(0.08), borderRadius: BorderRadius.circular(14)),
              child: Text('$text', style: TextStyle(fontSize: 15, color: Glass.text(context))),
            ),
            if (d['attachment_url'] != null && type == 'image')
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: ClipRRect(borderRadius: BorderRadius.circular(12), child: CachedChatImage(url: '${d['attachment_url']}', name: d['attachment_name'] as String?, width: 240)),
              ),
            const SizedBox(height: 12),
            Text('Sent by ${d['sender_name'] ?? 'Unknown'} in ${d['chat_name']}', style: TextStyle(fontSize: 12.5, color: Glass.muted(context))),
            Text('Sent ${_stamp(d['sent_at'])}', style: TextStyle(fontSize: 12.5, color: Glass.muted(context))),
            if (d['deleted'] == true)
              Text('Deleted ${_stamp(d['deleted_at'])}${d['deleted_by_name'] != null ? ' by ${d['deleted_by_name']}' : ''}',
                  style: const TextStyle(fontSize: 12.5, color: Color(0xFFDC2626), fontWeight: FontWeight.w700)),
          ]),
        ),
      ),
    ),
  );
}

/// Who reacted with what.
Future<void> showReactionDetails(BuildContext context, int messageId) async {
  List<Map<String, dynamic>> rows;
  try {
    rows = await Api.list('/team-chat/messages/$messageId/reactions');
  } catch (e) {
    return;
  }
  if (!context.mounted) return;
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) => Padding(
      padding: const EdgeInsets.all(12),
      child: GlassCard(
        opacity: 0.9,
        radius: 24,
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: SafeArea(
          top: false,
          child: ListView(shrinkWrap: true, children: [
            Padding(padding: const EdgeInsets.fromLTRB(18, 8, 18, 6), child: Text('${rows.length} reaction${rows.length == 1 ? '' : 's'}', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5, color: Glass.text(context)))),
            for (final r in rows)
              ListTile(
                dense: true,
                leading: ChatAvatar(name: '${r['name']}', url: r['avatar'] as String?, radius: 17),
                title: Text('${r['name']}', style: TextStyle(fontWeight: FontWeight.w700, color: Glass.text(context))),
                trailing: Text('${r['emoji']}', style: const TextStyle(fontSize: 22)),
              ),
          ]),
        ),
      ),
    ),
  );
}

/// ⭐ Starred messages across every chat (or one chat). Tap one to open the chat at that message.
class StarredMessagesPage extends StatefulWidget {
  const StarredMessagesPage({super.key, this.chatId});
  final int? chatId;
  @override
  State<StarredMessagesPage> createState() => _StarredMessagesPageState();
}

class _StarredMessagesPageState extends State<StarredMessagesPage> {
  late Future<List<Map<String, dynamic>>> _f = _load();
  Future<List<Map<String, dynamic>>> _load() => Api.list('/team-chat/starred', query: {if (widget.chatId != null) 'chat_id': widget.chatId});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.transparent,
        extendBodyBehindAppBar: true,
        appBar: const GlassAppBar(title: Text('Starred messages')),
        body: GlassBackground(
          child: SafeArea(
            child: RefreshIndicator(
              onRefresh: () async { setState(() => _f = _load()); await _f; },
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _f,
                builder: (_, s) {
                  if (s.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
                  if (s.hasError) return ListView(children: [Padding(padding: const EdgeInsets.all(32), child: Text(apiErrorMessage(s.error!), textAlign: TextAlign.center))]);
                  final rows = s.data ?? const [];
                  if (rows.isEmpty) {
                    return ListView(physics: teamScrollPhysics, children: [
                      const SizedBox(height: 90),
                      const Icon(Icons.star_border_rounded, size: 64, color: Glass.accentSoft),
                      const SizedBox(height: 10),
                      Center(child: Text('No starred messages', style: TextStyle(color: Glass.muted(context), fontWeight: FontWeight.w600))),
                      Padding(padding: const EdgeInsets.all(20), child: Text('Long-press a message and tap Star to keep it here.', textAlign: TextAlign.center, style: TextStyle(color: Glass.muted(context)))),
                    ]);
                  }
                  return ListView.builder(
                    physics: teamScrollPhysics,
                    padding: const EdgeInsets.fromLTRB(14, 8, 14, 30),
                    itemCount: rows.length,
                    itemBuilder: (_, i) {
                      final m = rows[i];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: GlassCard(
                          padding: EdgeInsets.zero,
                          child: ListTile(
                            onTap: () => context.push('/team-chat/${m['chat_id']}?m=${m['id']}'),
                            leading: ChatAvatar(name: '${m['chat_name']}'),
                            title: Text('${m['sender_name']} · ${m['chat_name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w800, color: Glass.text(context))),
                            subtitle: Text('${m['text'] ?? m['type']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: Glass.muted(context))),
                            trailing: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                              const Icon(Icons.star_rounded, color: Color(0xFFF59E0B), size: 18),
                              Text(teamDay(m['created_at']), style: TextStyle(fontSize: 10.5, color: Glass.muted(context))),
                            ]),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ),
      );
}
