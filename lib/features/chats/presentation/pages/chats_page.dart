import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:unichat_mobile_app/core/constants/app_colors.dart';
import 'package:unichat_mobile_app/core/permissions/permission_guard.dart';
import 'package:unichat_mobile_app/core/theme/app_theme.dart';
import 'package:unichat_mobile_app/core/utils/format_utils.dart';
import 'package:unichat_mobile_app/core/widgets/app_avatar.dart';
import 'package:unichat_mobile_app/features/chats/presentation/providers/chats_provider.dart';

class ChatsPage extends ConsumerStatefulWidget {
  const ChatsPage({super.key});
  @override
  ConsumerState<ChatsPage> createState() => _ChatsPageState();
}

class _ChatsPageState extends ConsumerState<ChatsPage> {
  final _searchCtrl = TextEditingController();
  bool _showSearch = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The bottom-nav tab bypasses the module catalogue's own permission gating entirely (it's
    // hardcoded in MainShell, not driven by AppModules) — self-check here so a role without
    // chat access can't reach it just by tapping the tab.
    if (!PermissionGuard.can('wa_chat.chats.view')) {
      return Scaffold(
        appBar: AppBar(title: const Text('Chats')),
        body: Center(
          child: Text("You don't have access to this section",
              style: TextStyle(color: context.mutedColor)),
        ),
      );
    }

    final filter   = ref.watch(chatFilterProvider);
    final search   = ref.watch(chatSearchProvider);
    final convsAsync = ref.watch(conversationsProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: _buildAppBar(),
      body: convsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _ErrorView(onRetry: () => ref.read(conversationsProvider.notifier).refresh()),
        data: (all) {
          final filtered = _applyFilters(all, filter, search);
          return Column(
            children: [
              _FilterChips(
                current: filter,
                onChange: (f) => ref.read(chatFilterProvider.notifier).state = f,
              ),
              Expanded(
                child: filtered.isEmpty
                    ? _EmptyState(filter: filter)
                    : RefreshIndicator(
                        onRefresh: () => ref.read(conversationsProvider.notifier).refresh(),
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          itemCount: filtered.length,
                          itemBuilder: (_, i) => _ChatTile(
                            conv: filtered[i],
                            onTap: () => context.push('/chats/${filtered[i]['id']}'),
                          ),
                        ),
                      ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {},
        backgroundColor: AppColors.primary,
        child: const Icon(Icons.chat, color: Colors.white),
      ),
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
      backgroundColor: AppColors.primaryDark,
      elevation: 0,
      title: _showSearch
          ? TextField(
              controller: _searchCtrl,
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: 'Search conversations…',
                hintStyle: TextStyle(color: Colors.white54),
                border: InputBorder.none,
              ),
              onChanged: (v) => ref.read(chatSearchProvider.notifier).state = v,
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Chats',
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                Consumer(builder: (_, ref, __) {
                  final count = ref.watch(conversationsProvider).value?.length ?? 0;
                  return Text('$count conversations',
                      style: const TextStyle(color: Colors.white60, fontSize: 11));
                }),
              ],
            ),
      actions: [
        IconButton(
          icon: Icon(_showSearch ? Icons.close : Icons.search, color: Colors.white),
          onPressed: () {
            setState(() => _showSearch = !_showSearch);
            if (!_showSearch) {
              _searchCtrl.clear();
              ref.read(chatSearchProvider.notifier).state = '';
            }
          },
        ),
        IconButton(
          icon: const Icon(Icons.notifications_outlined, color: Colors.white),
          onPressed: () => context.push('/notifications'),
        ),
      ],
    );
  }

  List<Map<String, dynamic>> _applyFilters(
    List<Map<String, dynamic>> all,
    String filter,
    String search,
  ) {
    var result = all;
    if (filter == 'unread')     result = result.where((c) => (c['unread_count'] as int? ?? 0) > 0).toList();
    if (filter == 'mine')       result = result.where((c) => c['assigned_to'] != null).toList();
    if (filter == 'ai')        result = result.where((c) => c['ai_handling'] == true).toList();
    if (filter == 'unassigned') result = result.where((c) => c['assigned_to'] == null).toList();
    if (search.isNotEmpty) {
      final q = search.toLowerCase();
      result = result.where((c) {
        final name = (c['contact_name'] as String? ?? c['name'] as String? ?? '').toLowerCase();
        final msg  = lastMessagePreview(c).toLowerCase();
        return name.contains(q) || msg.contains(q);
      }).toList();
    }
    return result;
  }
}

/// `last_message` on a conversation is the whole `WaMessage` row (Eloquent relation,
/// snake-cased on serialize), not a plain string — `{content: {body}, type, ...}`. Reading
/// it as `as String?` throws a cast error the instant a conversation actually has one.
/// Non-text types (image/voice/video/etc.) already get a placeholder body like "[Image]"
/// baked in server-side; the `type` fallback here only covers the rare case that's missing.
String lastMessagePreview(Map<String, dynamic> conv) {
  final last = conv['last_message'] as Map<String, dynamic>?;
  if (last == null) return '';
  final body = (last['content'] as Map<String, dynamic>?)?['body'] as String?;
  if (body != null && body.isNotEmpty) return body;
  final type = last['type'] as String?;
  return (type != null && type != 'text') ? '[$type]' : '';
}

class _FilterChips extends StatelessWidget {
  final String current;
  final void Function(String) onChange;
  const _FilterChips({required this.current, required this.onChange});

  static const _filters = [
    ('all', 'All'),
    ('unread', 'Unread'),
    ('mine', 'Mine'),
    ('ai', 'AI'),
    ('unassigned', 'Unassigned'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      height: 46,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        scrollDirection: Axis.horizontal,
        itemCount: _filters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final (key, label) = _filters[i];
          final sel = current == key;
          return FilterChip(
            label: Text(label),
            selected: sel,
            onSelected: (_) => onChange(key),
            backgroundColor: Colors.grey.shade100,
            selectedColor: AppColors.primary,
            checkmarkColor: Colors.white,
            labelStyle: TextStyle(
              color: sel ? Colors.white : AppColors.textSecondary,
              fontSize: 12,
              fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          );
        },
      ),
    );
  }
}

class _ChatTile extends StatelessWidget {
  final Map<String, dynamic> conv;
  final VoidCallback onTap;
  const _ChatTile({required this.conv, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final name    = conv['contact_name'] as String? ?? conv['name'] as String? ?? 'Unknown';
    final lastMsg = lastMessagePreview(conv);
    final unread  = conv['unread_count']  as int?    ?? 0;
    final phone   = conv['phone']         as String? ?? '';
    // The backend doesn't send `ai_handling` on conversation list rows today — this always
    // evaluates false, which is why the "AI" filter chip never matches anything either
    // (chatFilterProvider's 'ai' case above). Not a crash, just not wired up server-side yet.
    final isAi    = conv['ai_handling']   as bool?   ?? false;
    final rawTs   = conv['updated_at']    as String? ?? conv['last_message_at'] as String?;
    final ts      = rawTs != null ? DateTime.tryParse(rawTs) : null;

    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
          ),
          child: Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  AppAvatar(name: name, size: 50),
                  if (isAi)
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          color: AppColors.accent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.smart_toy, size: 10, color: Colors.white),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            style: TextStyle(
                              fontWeight: unread > 0 ? FontWeight.w800 : FontWeight.w600,
                              fontSize: 15,
                              color: AppColors.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          FormatUtils.chatTime(ts),
                          style: TextStyle(
                            fontSize: 11,
                            color: unread > 0 ? AppColors.primary : AppColors.textLight,
                            fontWeight: unread > 0 ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            lastMsg.isEmpty ? phone : lastMsg,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              color: unread > 0 ? AppColors.textPrimary : AppColors.textSecondary,
                              fontWeight: unread > 0 ? FontWeight.w600 : FontWeight.normal,
                            ),
                          ),
                        ),
                        if (unread > 0)
                          Container(
                            constraints: const BoxConstraints(minWidth: 20),
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '$unread',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String filter;
  const _EmptyState({required this.filter});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            filter == 'all' ? 'No conversations yet' : 'No conversations match this filter',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 16),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorView({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off, size: 64, color: AppColors.textLight),
          const SizedBox(height: 16),
          const Text('Could not load chats', style: TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
