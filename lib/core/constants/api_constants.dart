class ApiConstants {
  ApiConstants._();

  static const laravelBase = 'https://flowexa-api.univexa.in/api/v1';
  static const nodeBase    = 'https://unichatwa.univexa.in';
  static const socketUrl   = 'wss://unichatwa.univexa.in';

  /// Origin the Laravel API is served from, without the `/api/v1` suffix — needed to
  /// resolve `Storage::disk('public')` paths (e.g. `avatars/6/x.jpg`) into loadable URLs,
  /// the same way the web frontend does (`SettingsPage.tsx`: `` `/storage/${u.avatar}` ``).
  static const laravelOrigin = 'https://flowexa-api.univexa.in';

  static const connectTimeout = Duration(seconds: 30);
  static const receiveTimeout = Duration(seconds: 30);
}

/// The backend returns file fields (currently just `User.avatar`) as a bare
/// `storage/app/public` relative path, not a full URL — every client is expected to prefix
/// it itself. Returns null for an absent/empty path so callers can fall back to initials.
String? resolveStorageUrl(String? path) {
  if (path == null || path.isEmpty) return null;
  if (path.startsWith('http://') || path.startsWith('https://')) return path;
  return '${ApiConstants.laravelOrigin}/storage/$path';
}
