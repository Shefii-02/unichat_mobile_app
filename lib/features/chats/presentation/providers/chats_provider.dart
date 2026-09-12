import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:unichat_mobile_app/core/network/dio_client.dart';

// ── Search / filter state ─────────────────────────────────────────────────────
final chatSearchProvider = StateProvider<String>((ref) => '');
final chatFilterProvider = StateProvider<String>((ref) => 'all');

// ── All conversations from Laravel API ────────────────────────────────────────
class ConversationsNotifier extends AsyncNotifier<List<Map<String, dynamic>>> {
  @override
  FutureOr<List<Map<String, dynamic>>> build() => _fetch();

  Future<List<Map<String, dynamic>>> _fetch() async {
    final res = await DioClient.laravelDio.get('/conversations', queryParameters: {
      'per_page': 100,
    });
    final data = res.data as Map<String, dynamic>;
    final list = data['conversations'] as List? ?? data['data'] as List? ?? [];
    return list.cast<Map<String, dynamic>>();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_fetch);
  }
}

final conversationsProvider =
    AsyncNotifierProvider<ConversationsNotifier, List<Map<String, dynamic>>>(
  ConversationsNotifier.new,
);

// ── Messages for a conversation ───────────────────────────────────────────────
final conversationMessagesProvider =
    FutureProvider.family<List<Map<String, dynamic>>, int>((ref, id) async {
  final res = await DioClient.laravelDio.get('/conversations/$id/messages');
  final data = res.data as Map<String, dynamic>;
  final list = data['messages'] as List? ?? data['data'] as List? ?? [];
  return list.cast<Map<String, dynamic>>();
});
