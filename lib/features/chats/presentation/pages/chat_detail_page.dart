import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:unichat_mobile_app/core/constants/app_colors.dart';
import 'package:unichat_mobile_app/core/network/dio_client.dart';
import 'package:unichat_mobile_app/core/widgets/app_avatar.dart';
import 'package:unichat_mobile_app/core/widgets/whatsapp_bubble.dart';
import 'package:unichat_mobile_app/features/chats/presentation/providers/chats_provider.dart';
import 'dart:async';

class ChatDetailPage extends ConsumerStatefulWidget {
  const ChatDetailPage({super.key, required this.conversationId});
  final int conversationId;
  @override
  ConsumerState<ChatDetailPage> createState() => _ChatDetailPageState();
}

class _ChatDetailPageState extends ConsumerState<ChatDetailPage> {
  final _scroll = ScrollController();
  final _input  = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _scroll.dispose();
    _input.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    _input.clear();
    setState(() => _sending = true);
    try {
      await DioClient.laravelDio.post(
        '/conversations/${widget.conversationId}/messages',
        data: {'message': text, 'type': 'text'},
      );
      // Invalidate messages to reload
      ref.invalidate(conversationMessagesProvider(widget.conversationId));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Send failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final conv = ref.watch(conversationsProvider).value?.firstWhere(
      (c) => (c['id'] as int?) == widget.conversationId,
      orElse: () => <String, dynamic>{},
    );
    final name = conv?['contact_name'] as String? ?? '#${widget.conversationId}';
    final msgsAsync = ref.watch(conversationMessagesProvider(widget.conversationId));

    return Scaffold(
      backgroundColor: AppColors.bgLight,
      appBar: AppBar(
        backgroundColor: AppColors.primaryDark,
        title: Row(
          children: [
            AppAvatar(name: name, size: 36),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
                const Text('tap for info',
                    style: TextStyle(fontSize: 11, color: Colors.white60)),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
              icon: const Icon(Icons.call_outlined, color: Colors.white), onPressed: () {}),
          IconButton(
              icon: const Icon(Icons.more_vert, color: Colors.white), onPressed: () {}),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: msgsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => const Center(child: Text('Could not load messages')),
              data: (messages) {
                _scrollToBottom();
                if (messages.isEmpty) {
                  return const Center(
                    child: Text('No messages yet', style: TextStyle(color: AppColors.textLight)),
                  );
                }
                return ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: messages.length,
                  itemBuilder: (_, i) {
                    final m = messages[i];
                    final fromMe = m['direction'] == 'outbound' || m['from_me'] == true;
                    return WhatsAppBubble(message: m, isSent: fromMe);
                  },
                );
              },
            ),
          ),
          _inputBar(),
        ],
      ),
    );
  }

  Widget _inputBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.emoji_emotions_outlined, color: AppColors.textLight),
              onPressed: () {},
            ),
            Expanded(
              child: TextField(
                controller: _input,
                onSubmitted: (_) => _send(),
                decoration: const InputDecoration(
                  hintText: 'Type a message',
                  hintStyle: TextStyle(color: AppColors.textLight),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(horizontal: 4),
                ),
                maxLines: 4,
                minLines: 1,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.attach_file, color: AppColors.textLight),
              onPressed: () {},
            ),
            _sending
                ? const SizedBox(
                    width: 40, height: 40,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : GestureDetector(
                    onTap: _send,
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: const BoxDecoration(
                          color: AppColors.primary, shape: BoxShape.circle),
                      child: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}
