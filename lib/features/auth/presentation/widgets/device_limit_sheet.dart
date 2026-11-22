import 'package:flutter/material.dart';
import 'package:unichat_mobile_app/core/theme/app_theme.dart';
import 'package:unichat_mobile_app/features/auth/data/device_auth_repository.dart';

/// What happened after the person tapped "Remove" on a phone.
sealed class DeviceLimitOutcome {
  const DeviceLimitOutcome();
}

/// Signed in — the sheet closes and the app goes home.
class DeviceLimitDone extends DeviceLimitOutcome {
  const DeviceLimitDone();
}

/// Still over the limit (another phone signed in meanwhile, or the limit is higher than one) — keep the sheet open with the fresh list.
class DeviceLimitAgain extends DeviceLimitOutcome {
  const DeviceLimitAgain(this.limit);
  final DeviceLimitException limit;
}

/// Something else went wrong — show the message, keep the sheet open.
class DeviceLimitFailed extends DeviceLimitOutcome {
  const DeviceLimitFailed(this.message);
  final String message;
}

/// "This account is already signed in on N phones — remove one to continue." Shown after an email + password sign-in that hit the
/// limit. Removing a phone repeats the sign-in; when that succeeds the sheet closes and the app opens the home screen.
class DeviceLimitSheet extends StatefulWidget {
  const DeviceLimitSheet({super.key, required this.limit, required this.onRemove});

  final DeviceLimitException limit;

  /// Removes the phone with this id and repeats the sign-in.
  final Future<DeviceLimitOutcome> Function(int deviceId) onRemove;

  @override
  State<DeviceLimitSheet> createState() => _DeviceLimitSheetState();
}

class _DeviceLimitSheetState extends State<DeviceLimitSheet> {
  late DeviceLimitException _limit = widget.limit;
  int? _removing;
  String? _error;

  Future<void> _remove(LinkedDevice d) async {
    setState(() { _removing = d.id; _error = null; });
    final outcome = await widget.onRemove(d.id);
    if (!mounted) return;
    switch (outcome) {
      case DeviceLimitDone():
        Navigator.of(context).pop(true);
      case DeviceLimitAgain(:final limit):
        setState(() { _limit = limit; _removing = null; });
      case DeviceLimitFailed(:final message):
        setState(() { _error = message; _removing = null; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final busy = _removing != null;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(24, 8, 24, 24 + MediaQuery.of(context).viewInsets.bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.devices_other_rounded, size: 40, color: AppPalette.warning),
              const SizedBox(height: 12),
              Text('Device limit reached',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(_limit.message,
                  textAlign: TextAlign.center,
                  key: const ValueKey('limit-message'),
                  style: TextStyle(color: context.mutedColor, fontSize: 13, height: 1.4)),
              const SizedBox(height: 16),
              for (final d in _limit.devices)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: Icon(_platformIcon(d.platform)),
                    title: Text(d.name),
                    subtitle: Text(d.lastActiveAt != null ? 'Last active ${_ago(d.lastActiveAt!)}' : (d.platform ?? 'Unknown')),
                    trailing: _removing == d.id
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : TextButton(
                            key: ValueKey('remove-${d.id}'),
                            onPressed: busy ? null : () => _remove(d),
                            child: const Text('Remove'),
                          ),
                  ),
                ),
              if (_error != null) ...[
                const SizedBox(height: 4),
                Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppPalette.danger, fontSize: 13)),
              ],
              TextButton(
                onPressed: busy ? null : () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static IconData _platformIcon(String? p) => switch (p) {
        'ios' => Icons.phone_iphone_rounded,
        'android' => Icons.phone_android_rounded,
        'web' => Icons.language_rounded,
        _ => Icons.devices_rounded,
      };

  static String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inHours < 1) return '${d.inMinutes}m ago';
    if (d.inDays < 1) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }
}
