import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:unichat_mobile_app/core/constants/app_colors.dart';
import 'package:unichat_mobile_app/core/network/wa_chat_api_service.dart';
import 'package:unichat_mobile_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:unichat_mobile_app/features/chats/presentation/pages/wa_session_chat_room_page.dart';
import 'package:unichat_mobile_app/features/modules/_shared.dart';
import 'package:unichat_mobile_app/features/modules/module_providers.dart';

/// Full-text search over message content, across every WA Chat session the account's gateway key
/// can see — mirrors `frontend/src/pages/wa-chat/components/GlobalSearch.tsx`, as a dedicated page
/// rather than a header dropdown (the natural mobile shape for the same feature).
class GlobalSearchPage extends ConsumerStatefulWidget {
  const GlobalSearchPage({super.key, this.initialSessionId, this.initialSessionLabel});

  /// The session (`session_name`) the caller had open, if any — lets "Scope to this session" work
  /// without a picker. Search still works with no scope: `GET /api/search` with no `sessionId`
  /// covers every session the key can see.
  final String? initialSessionId;
  final String? initialSessionLabel;

  @override
  ConsumerState<GlobalSearchPage> createState() => _GlobalSearchPageState();
}

const _pageSize = 20;
const _debounceDuration = Duration(milliseconds: 300);

class _GlobalSearchPageState extends ConsumerState<GlobalSearchPage> {
  final _searchCtrl = TextEditingController();
  final _focusNode = FocusNode();
  Timer? _debounce;

  List<Rec> _hits = [];
  int _total = 0;
  bool _loading = false;
  String? _error;
  bool _scopeCurrent = false;
  bool _openingHit = false;

  @override
  void initState() {
    super.initState();
    _focusNode.requestFocus();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    final q = value.trim();
    if (q.isEmpty) {
      setState(() {
        _hits = [];
        _total = 0;
        _error = null;
        _loading = false;
      });
      return;
    }
    _debounce = Timer(_debounceDuration, () => _run(q, 0, append: false));
  }

  Future<void> _run(String q, int offset, {required bool append}) async {
    final apiKey = ref.read(authProvider).value?.waContactToken;
    if (apiKey == null || apiKey.isEmpty) {
      setState(() {
        _error = 'No WhatsApp Chat gateway key on this account yet.';
        _loading = false;
      });
      return;
    }
    setState(() {
      _loading = true;
      if (!append) _error = null;
    });
    try {
      final res = await WaChatApiService.search(
        apiKey,
        q: q,
        sessionId: _scopeCurrent ? widget.initialSessionId : null,
        limit: _pageSize,
        offset: offset,
      );
      final hits = (res['hits'] as List?)?.whereType<Map>().map((m) => m.cast<String, dynamic>()).toList() ?? [];
      if (!mounted) return;
      setState(() {
        _hits = append ? [..._hits, ...hits] : hits;
        _total = (res['total'] as num?)?.toInt() ?? _hits.length;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      final status = e is DioException ? e.response?.statusCode : null;
      setState(() {
        _error = status == 501
            ? 'Search is not available right now.'
            : status == 503
                ? 'Search is temporarily unavailable — try again.'
                : apiErrorMessage(e);
        if (!append) {
          _hits = [];
          _total = 0;
        }
        _loading = false;
      });
    }
  }

  void _loadMore() {
    final q = _searchCtrl.text.trim();
    if (q.isEmpty || _loading) return;
    _run(q, _hits.length, append: true);
  }

  Future<void> _openHit(Rec hit) async {
    if (_openingHit) return;
    setState(() => _openingHit = true);
    try {
      final apiKey = ref.read(authProvider).value?.waContactToken;
      final hitSessionId = str(hit['sessionId'], '');
      final chatId = str(hit['chatId'], '');
      if (apiKey == null || apiKey.isEmpty || hitSessionId.isEmpty || chatId.isEmpty) {
        throw Exception('Missing session or chat id on this result.');
      }
      final sessions = await ref.read(wahaSessionsProvider.future);
      final session = sessions.firstWhere(
        (s) => str(s['session_name'], '') == hitSessionId,
        orElse: () => <String, dynamic>{},
      );
      if (session.isEmpty) throw Exception('Could not find that session on this account.');
      final sessionName = str(session['session_name'], '');
      final chats = await WaChatApiService.getChats(sessionName, apiKey);
      final chat = chats.firstWhere((c) => str(c['id'], '') == chatId, orElse: () => <String, dynamic>{});
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => WaSessionChatRoomPage(
          sessionName: sessionName,
          sessionLabel: str(session['display_name'] ?? session['phone'], sessionName),
          apiKey: apiKey,
          chatId: chatId,
          chatName: chat.isNotEmpty ? str(chat['name'], 'Unknown') : chatId,
          isGroup: chat['isGroup'] == true,
          allChats: chats,
        ),
      ));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
    } finally {
      if (mounted) setState(() => _openingHit = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        backgroundColor: AppColors.primaryDark,
        elevation: 0,
        titleSpacing: 0,
        title: TextField(
          controller: _searchCtrl,
          focusNode: _focusNode,
          onChanged: _onQueryChanged,
          style: const TextStyle(color: Colors.white, fontSize: 15),
          cursorColor: Colors.white,
          decoration: InputDecoration(
            hintText: 'Search messages…',
            hintStyle: const TextStyle(color: Colors.white60),
            border: InputBorder.none,
            suffixIcon: _searchCtrl.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 20),
                    onPressed: () {
                      _searchCtrl.clear();
                      _onQueryChanged('');
                    },
                  ),
          ),
        ),
      ),
      body: Column(
        children: [
          if (widget.initialSessionId != null)
            Container(
              color: AppColors.primaryDark,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Row(
                children: [
                  Checkbox(
                    value: _scopeCurrent,
                    onChanged: (v) {
                      setState(() => _scopeCurrent = v ?? false);
                      final q = _searchCtrl.text.trim();
                      if (q.isNotEmpty) _run(q, 0, append: false);
                    },
                    fillColor: WidgetStateProperty.all(Colors.white),
                    checkColor: AppColors.primaryDark,
                  ),
                  Expanded(
                    child: Text(
                      'Scope to ${widget.initialSessionLabel ?? "current session"}',
                      style: const TextStyle(color: Colors.white70, fontSize: 12.5),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    final q = _searchCtrl.text.trim();
    if (q.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.search_rounded, size: 40, color: context.mutedColor.withValues(alpha: 0.4)),
            const SizedBox(height: 10),
            Text('Search across every message in your WhatsApp chats',
                textAlign: TextAlign.center, style: TextStyle(color: context.mutedColor, fontSize: 13)),
          ]),
        ),
      );
    }
    if (_loading && _hits.isEmpty) return const Center(child: CircularProgressIndicator());
    if (_error != null && _hits.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: context.mutedColor)),
        ),
      );
    }
    if (_hits.isEmpty) {
      return Center(child: Text('No messages found', style: TextStyle(color: context.mutedColor)));
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: _hits.length + 1,
      separatorBuilder: (_, __) => Divider(height: 1, color: context.lineColor),
      itemBuilder: (_, i) {
        if (i == _hits.length) {
          if (_hits.length >= _total) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: _loading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : OutlinedButton(onPressed: _loadMore, child: Text('Show more ($_total total)')),
            ),
          );
        }
        return _HitTile(hit: _hits[i], onTap: () => _openHit(_hits[i]));
      },
    );
  }
}

class _HitTile extends StatelessWidget {
  const _HitTile({required this.hit, required this.onTap});
  final Rec hit;
  final VoidCallback onTap;

  List<(String, bool)> _segments(String snippet) {
    if (snippet.isEmpty) return [('', false)];
    final parts = snippet.split(RegExp(r'</?mark>'));
    final out = <(String, bool)>[];
    for (var i = 0; i < parts.length; i++) {
      if (parts[i].isEmpty) continue;
      out.add((parts[i], i.isOdd));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final chatId = str(hit['chatId'], '');
    final ts = hit['timestamp'];
    final when_ = ts != null
        ? when(DateTime.fromMillisecondsSinceEpoch((num.tryParse('$ts') ?? 0).toInt() * 1000).toIso8601String())
        : '';
    final direction = str(hit['direction'], '');
    final segments = _segments(str(hit['snippet'], ''));

    return ListTile(
      onTap: onTap,
      leading: Icon(
        direction == 'outgoing' ? Icons.call_made_rounded : Icons.call_received_rounded,
        size: 18,
        color: context.mutedColor,
      ),
      title: Text(chatId, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        // The snippet's <mark> markers are highlight boundaries only — the surrounding body text is
        // NOT HTML and must never be parsed as such; each segment is rendered as a plain TextSpan.
        child: Text.rich(
          TextSpan(
            children: segments
                .map((s) => TextSpan(
                      text: s.$1,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: s.$2 ? AppColors.primaryDark : context.mutedColor,
                        fontWeight: s.$2 ? FontWeight.w700 : FontWeight.w400,
                        backgroundColor: s.$2 ? AppColors.primary.withValues(alpha: 0.15) : null,
                      ),
                    ))
                .toList(),
          ),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      trailing: when_.isEmpty ? null : Text(when_, style: TextStyle(fontSize: 10.5, color: context.mutedColor)),
    );
  }
}
