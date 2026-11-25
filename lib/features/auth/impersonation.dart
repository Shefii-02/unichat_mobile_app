import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:unichat_mobile_app/core/network/api.dart';
import 'package:unichat_mobile_app/core/permissions/permission_guard.dart';
import 'package:unichat_mobile_app/core/storage/local_storage.dart';
import 'package:unichat_mobile_app/core/storage/secure_storage.dart';
import 'package:unichat_mobile_app/features/auth/data/models/user_model.dart';
import 'package:unichat_mobile_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:unichat_mobile_app/core/nav/mobile_config_provider.dart';
import 'package:unichat_mobile_app/features/notifications/notification_providers.dart';

/// "Login as": the owner (or anyone given "Sign in as staff") opens the app as one of their staff to see exactly what that person sees.
/// The owner's own session is kept aside; a banner at the bottom offers "Switch back".
const _kName = 'imp_name';
const _kUser = 'imp_original_user';

/// The name of the person you are signed in as, or null when you are yourself.
class ImpersonatingNotifier extends Notifier<String?> {
  @override
  String? build() => LocalStorage.getString(_kName);
  void set(String? name) => state = name;
}

final impersonatingProvider = NotifierProvider<ImpersonatingNotifier, String?>(ImpersonatingNotifier.new);

/// Can this person use "Login as"? (the owner always; others only with the permission — the server checks again)
bool canLoginAs() => PermissionGuard.can('staff.login_as');

/// Sign in as [staffId]. Returns null on success, or a message to show.
Future<String?> startLoginAs(WidgetRef ref, int staffId) async {
  try {
    final res = await Api.post('/staff/$staffId/login-as');
    final token = res['access_token'] as String?;
    if (token == null) return 'Could not sign in as that person.';
    if (ref.read(impersonatingProvider) == null) {
      // keep the owner's own session so "Switch back" can restore it
      final own = await SecureStorageService.getToken();
      final user = LocalStorage.getJson(LocalStorage.kUser);
      if (own != null) await SecureStorageService.saveOriginalToken(own);
      if (user != null) await LocalStorage.setJson(_kUser, user);
    }
    await SecureStorageService.saveToken(token);
    final user = await ref.read(authRepositoryProvider).validateToken();
    await LocalStorage.setString(_kName, '${res['name'] ?? user.name}');
    ref.read(impersonatingProvider.notifier).set('${res['name'] ?? user.name}');
    ref.read(authProvider.notifier).switchTo(user);
    _refreshCaches(ref);
    return null;
  } catch (e) {
    final msg = e.toString();
    return msg.contains('403') ? 'You do not have permission to sign in as staff.' : 'Could not sign in as that person.';
  }
}

/// Back to your own account.
Future<void> switchBack(WidgetRef ref) async {
  final token = await SecureStorageService.getOriginalToken();
  final userJson = LocalStorage.getJson(_kUser);
  if (token == null) return;
  await SecureStorageService.saveToken(token);
  UserModel user;
  try {
    user = await ref.read(authRepositoryProvider).validateToken();
  } catch (_) {
    if (userJson == null) return;
    user = UserModel.fromJson(Map<String, dynamic>.from(userJson));
    await LocalStorage.setJson(LocalStorage.kUser, userJson);
    PermissionGuard.setPermissions(user.permissions, user.role);
    PermissionGuard.setEntitlements(user.entitledModules);
  }
  await SecureStorageService.deleteOriginalToken();
  await LocalStorage.remove(_kName);
  await LocalStorage.remove(_kUser);
  ref.read(impersonatingProvider.notifier).set(null);
  ref.read(authProvider.notifier).switchTo(user);
  _refreshCaches(ref);
}

/// Screens keep what they loaded for the previous person — drop it so the next screen asks again.
void _refreshCaches(WidgetRef ref) {
  ref.invalidate(mobileConfigProvider);
  ref.invalidate(notificationBadgeProvider);
}
