import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:unichat_mobile_app/core/network/dio_client.dart';

final contactsSearchProvider = StateProvider<String>((ref) => '');

class ContactsNotifier extends AsyncNotifier<List<Map<String, dynamic>>> {
  @override
  FutureOr<List<Map<String, dynamic>>> build() => _fetch();

  Future<List<Map<String, dynamic>>> _fetch() async {
    final search = ref.read(contactsSearchProvider);
    final res = await DioClient.laravelDio.get('/contacts', queryParameters: {
      'per_page': 50,
      if (search.isNotEmpty) 'search': search,
    });
    final data = res.data as Map<String, dynamic>;
    return (data['data'] as List).cast<Map<String, dynamic>>();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_fetch);
  }
}

final contactsProvider = AsyncNotifierProvider<ContactsNotifier, List<Map<String, dynamic>>>(ContactsNotifier.new);

final contactDetailProvider = FutureProvider.family<Map<String, dynamic>, int>((ref, id) async {
  final res = await DioClient.laravelDio.get('/contacts/$id');
  return res.data as Map<String, dynamic>;
});
