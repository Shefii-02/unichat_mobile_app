import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:unichat_mobile_app/core/network/dio_client.dart';

// ── Filter state ──────────────────────────────────────────────────────────────
final leadsStatusFilterProvider = StateProvider<String?>((ref) => null);

// ── Paginated leads list ──────────────────────────────────────────────────────
class LeadsNotifier extends AsyncNotifier<List<Map<String, dynamic>>> {
  int _page = 1;
  bool _hasMore = true;

  @override
  FutureOr<List<Map<String, dynamic>>> build() => _fetch(reset: true);

  Future<List<Map<String, dynamic>>> _fetch({bool reset = false}) async {
    if (reset) { _page = 1; _hasMore = true; }
    final status = ref.read(leadsStatusFilterProvider);
    final res = await DioClient.laravelDio.get('/leads', queryParameters: {
      'page': _page,
      'per_page': 20,
      if (status != null) 'status': status,
    });
    final data = res.data as Map<String, dynamic>;
    final items = (data['data'] as List).cast<Map<String, dynamic>>();
    _hasMore = (data['meta']?['current_page'] ?? 1) < (data['meta']?['last_page'] ?? 1);
    return items;
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _fetch(reset: true));
  }

  Future<void> loadMore() async {
    if (!_hasMore || state.isLoading) return;
    _page++;
    final current = state.value ?? [];
    state = await AsyncValue.guard(() async {
      final more = await _fetch();
      return [...current, ...more];
    });
  }

  bool get hasMore => _hasMore;
}

final leadsProvider = AsyncNotifierProvider<LeadsNotifier, List<Map<String, dynamic>>>(LeadsNotifier.new);

// ── Single lead detail ────────────────────────────────────────────────────────
final leadDetailProvider = FutureProvider.family<Map<String, dynamic>, int>((ref, id) async {
  final res = await DioClient.laravelDio.get('/leads/$id');
  return res.data as Map<String, dynamic>;
});
