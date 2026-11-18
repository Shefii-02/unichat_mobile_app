import 'package:flutter/material.dart';
import 'package:unichat_mobile_app/core/network/api.dart';
import 'package:unichat_mobile_app/features/team_chat/team_chat_data.dart';
import 'package:unichat_mobile_app/features/team_chat/team_chat_style.dart';
import 'package:unichat_mobile_app/features/team_chat/team_media.dart';
import 'package:url_launcher/url_launcher.dart';

/// Media, links and docs shared in a chat (WhatsApp style): tabs with counts, a photo/video grid that opens
/// the swipe gallery, document list (PDF opens in-app), voice notes and links. Files are fetched into the
/// on-device cache the first time they are opened.
class ChatMediaPage extends StatefulWidget {
  const ChatMediaPage({super.key, required this.chatId, required this.title});
  final int chatId;
  final String title;
  @override
  State<ChatMediaPage> createState() => _ChatMediaPageState();
}

class _ChatMediaPageState extends State<ChatMediaPage> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 4, vsync: this);
  Map<String, int> _counts = {};

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    String label(String n, String k) => (_counts[k] ?? 0) > 0 ? '$n ${_counts[k]}' : n;
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: GlassAppBar(
        title: Text(widget.title, style: const TextStyle(fontWeight: FontWeight.w800)),
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: Glass.accent,
          labelColor: Glass.accentDeep,
          unselectedLabelColor: Glass.muted(context),
          tabs: [Tab(text: label('Media', 'media')), Tab(text: label('Docs', 'docs')), Tab(text: label('Voice', 'audio')), Tab(text: label('Links', 'links'))],
        ),
      ),
      body: GlassBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.only(top: kToolbarHeight + 48),
            child: TabBarView(controller: _tabs, children: [
              for (final t in const ['media', 'docs', 'audio', 'links'])
                _MediaTab(chatId: widget.chatId, type: t, onCounts: (c) { if (mounted && _counts.isEmpty) setState(() => _counts = c); }),
            ]),
          ),
        ),
      ),
    );
  }
}

class _MediaTab extends StatefulWidget {
  const _MediaTab({required this.chatId, required this.type, required this.onCounts});
  final int chatId;
  final String type;
  final void Function(Map<String, int>) onCounts;
  @override
  State<_MediaTab> createState() => _MediaTabState();
}

class _MediaTabState extends State<_MediaTab> with AutomaticKeepAliveClientMixin {
  final _items = <Map<String, dynamic>>[];
  final _scroll = ScrollController();
  bool _loading = true, _more = true, _busy = false;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() { if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 300) _load(); });
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_busy || !_more) return;
    _busy = true;
    try {
      final res = await Api.raw.get('/team-chat/chats/${widget.chatId}/media', queryParameters: {
        'type': widget.type,
        'limit': 60,
        if (_items.isNotEmpty) 'before_id': _items.last['id'],
      });
      final d = res.data is Map ? res.data as Map : const {};
      final rows = (d['data'] is List ? d['data'] as List : const []).whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
      if (d['counts'] is Map) widget.onCounts({for (final e in (d['counts'] as Map).entries) '${e.key}': (e.value as num).toInt()});
      if (!mounted) return;
      setState(() { _items.addAll(rows); _more = rows.length >= 60; _loading = false; _error = null; });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = apiErrorMessage(e); });
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null && _items.isEmpty) return Center(child: Text(_error!));
    if (_items.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(widget.type == 'links' ? Icons.link_rounded : Icons.photo_library_outlined, size: 56, color: Glass.accentSoft),
        const SizedBox(height: 8),
        Text('Nothing shared yet', style: TextStyle(color: Glass.muted(context), fontWeight: FontWeight.w600)),
      ]));
    }
    switch (widget.type) {
      case 'media':
        final gallery = [
          for (final m in _items.reversed)
            MediaItem(url: '${m['url']}', isVideo: m['type'] == 'video', name: m['name'] as String?, sender: m['sender_name'] as String?, time: '${teamDay(m['created_at'])} ${teamTime(m['created_at'])}'),
        ];
        return GridView.builder(
          controller: _scroll,
          physics: teamScrollPhysics,
          padding: const EdgeInsets.all(10),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 6, crossAxisSpacing: 6),
          itemCount: _items.length,
          itemBuilder: (_, i) {
            final m = _items[i];
            final isVideo = m['type'] == 'video';
            return GestureDetector(
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => MediaGalleryPage(items: gallery, initialIndex: gallery.length - 1 - i))),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(fit: StackFit.expand, children: [
                  if (isVideo) Container(color: Colors.black87) else CachedChatImage(url: '${m['url']}', name: m['name'] as String?, width: 140),
                  if (isVideo) const Center(child: Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 38)),
                ]),
              ),
            );
          },
        );
      case 'docs':
        return ListView.builder(
          controller: _scroll,
          physics: teamScrollPhysics,
          padding: const EdgeInsets.all(12),
          itemCount: _items.length,
          itemBuilder: (_, i) {
            final m = _items[i];
            final pdf = '${m['mime'] ?? ''}'.contains('pdf') || '${m['name']}'.toLowerCase().endsWith('.pdf');
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GlassCard(
                padding: EdgeInsets.zero,
                child: ListTile(
                  onTap: () => openTeamFile(context, url: '${m['url']}', name: '${m['name'] ?? 'File'}', mime: m['mime'] as String?),
                  leading: Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(color: (pdf ? Colors.red : Glass.accent).withOpacity(0.14), borderRadius: BorderRadius.circular(10)),
                    child: Icon(pdf ? Icons.picture_as_pdf_rounded : Icons.insert_drive_file_rounded, color: pdf ? Colors.red : Glass.accent),
                  ),
                  title: Text('${m['name'] ?? 'File'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, color: Glass.text(context))),
                  subtitle: Text('${m['sender_name'] ?? ''} · ${teamDay(m['created_at'])}', style: TextStyle(color: Glass.muted(context), fontSize: 12)),
                ),
              ),
            );
          },
        );
      case 'audio':
        return ListView.builder(
          controller: _scroll,
          physics: teamScrollPhysics,
          padding: const EdgeInsets.all(12),
          itemCount: _items.length,
          itemBuilder: (_, i) {
            final m = _items[i];
            final s = (m['duration'] as num?)?.toInt() ?? 0;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GlassCard(
                padding: EdgeInsets.zero,
                child: ListTile(
                  onTap: () => openTeamFile(context, url: '${m['url']}', name: '${m['name'] ?? 'voice.m4a'}', mime: m['mime'] as String?),
                  leading: const CircleAvatar(backgroundColor: Glass.accent, child: Icon(Icons.mic_rounded, color: Colors.white)),
                  title: Text('Voice message · ${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}', style: TextStyle(fontWeight: FontWeight.w700, color: Glass.text(context))),
                  subtitle: Text('${m['sender_name'] ?? ''} · ${teamDay(m['created_at'])} ${teamTime(m['created_at'])}', style: TextStyle(color: Glass.muted(context), fontSize: 12)),
                ),
              ),
            );
          },
        );
      default:
        return ListView.builder(
          controller: _scroll,
          physics: teamScrollPhysics,
          padding: const EdgeInsets.all(12),
          itemCount: _items.length,
          itemBuilder: (_, i) {
            final m = _items[i];
            final links = (m['links'] as List? ?? const []).map((e) => '$e').toList();
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GlassCard(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  for (final l in links)
                    InkWell(
                      onTap: () => launchUrl(Uri.parse(l), mode: LaunchMode.externalApplication),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(children: [
                          const Icon(Icons.link_rounded, size: 18, color: Glass.accent),
                          const SizedBox(width: 8),
                          Expanded(child: Text(l, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Glass.accentDeep, decoration: TextDecoration.underline))),
                        ]),
                      ),
                    ),
                  const SizedBox(height: 4),
                  Text('${m['sender_name'] ?? ''} · ${teamDay(m['created_at'])}', style: TextStyle(color: Glass.muted(context), fontSize: 12)),
                ]),
              ),
            );
          },
        );
    }
  }
}
