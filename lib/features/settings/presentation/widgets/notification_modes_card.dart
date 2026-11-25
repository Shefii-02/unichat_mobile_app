import 'package:flutter/material.dart';
import 'package:unichat_mobile_app/core/constants/app_colors.dart';
import 'package:unichat_mobile_app/features/modules/_shared.dart';
import 'package:unichat_mobile_app/services/notification_tones.dart';
import 'package:unichat_mobile_app/services/push_service.dart';

const _groups = <(String, String, String)>[
  ('lead_popup', 'New lead offers & AI hand-offs', 'Pop-ups waiting for your answer'),
  ('lead', 'Lead activity', 'Assigned, transferred, recalled, stage changes, SLA'),
  ('conversation', 'Conversations & team chat', 'New conversation, chat messages, mentions'),
  ('general', 'Everything else', 'Campaigns, wallet, WhatsApp session, HR …'),
];
const _modes = <String, String>{'sound': '🔔 With tone', 'silent': '🔕 Notification only', 'off': '🚫 Off'};

/// Settings → Notifications: per kind, a notification with its tone / notification only / none — for the account (web + phones),
/// and per phone ("This phone" first) so one device can differ from the rest.
class NotificationModesCard extends StatefulWidget {
  const NotificationModesCard({super.key});
  @override
  State<NotificationModesCard> createState() => _NotificationModesCardState();
}

class _NotificationModesCardState extends State<NotificationModesCard> {
  Map<String, String> _account = {};
  List<Map<String, dynamic>> _devices = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Map<String, String> _modesOf(dynamic v) => v is Map ? {for (final e in v.entries) '${e.key}': '${e.value}'} : <String, String>{};

  Future<void> _load() async {
    try {
      final me = await Api.one('/notification-preferences/me');
      final dv = await Api.list('/notification-preferences/devices', query: {if (PushService.instance.token != null) 'fcm_token': PushService.instance.token});
      dv.sort((a, b) => (b['current'] == true ? 1 : 0) - (a['current'] == true ? 1 : 0));
      if (!mounted) return;
      setState(() {
        _account = _modesOf(me['modes']);
        _devices = dv;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = apiErrorMessage(e); });
    }
  }

  Future<void> _setAccount(String group, String mode) async {
    final next = {..._account, group: mode};
    setState(() => _account = next);
    try {
      await Api.raw.put('/notification-preferences/me', data: {'modes': next});
      if (mode == 'sound') NotificationTones.play(group);   // let them hear it
    } catch (e) {
      _toast(apiErrorMessage(e));
      _load();
    }
  }

  Future<void> _setDevice(Map<String, dynamic> d, String group, String? mode) async {
    final next = _modesOf(d['modes']);
    if (mode == null) { next.remove(group); } else { next[group] = mode; }
    setState(() => d['modes'] = next);
    try {
      await Api.raw.put('/notification-preferences/devices/${d['id']}', data: {'modes': next});
    } catch (e) {
      _toast(apiErrorMessage(e));
      _load();
    }
  }

  void _toast(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  String _deviceLabel(Map<String, dynamic> d) {
    final name = d['name'] as String?;
    final base = (name != null && name.isNotEmpty) ? name : (d['type'] == 'web' ? 'Web browser' : d['type'] == 'ios' ? 'iPhone' : 'Android phone');
    return d['current'] == true ? 'This phone · $base' : base;
  }

  Widget _picker(String? value, void Function(String?) onChanged, {bool inherit = false}) {
    return DropdownButton<String?>(
      value: value,
      underline: const SizedBox.shrink(),
      isDense: true,
      style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
      onChanged: onChanged,
      items: [
        if (inherit) const DropdownMenuItem<String?>(value: null, child: Text('Same as mine')),
        for (final e in _modes.entries) DropdownMenuItem<String?>(value: e.key, child: Text(e.value)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
    if (_error != null) return Padding(padding: const EdgeInsets.all(16), child: Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 12)));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Padding(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Text('How you get notified', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
      ),
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: Text('For each kind: a notification with its tone, a notification only (no tone), or none. Applies on the web and your phones.', style: TextStyle(fontSize: 11.5, color: AppColors.textLight)),
      ),
      for (final g in _groups)
        ListTile(
          dense: true,
          title: Text(g.$2, style: const TextStyle(fontSize: 14)),
          subtitle: Text(g.$3, style: const TextStyle(fontSize: 11.5, color: AppColors.textLight)),
          trailing: _picker(_account[g.$1] ?? 'sound', (v) { if (v != null) _setAccount(g.$1, v); }),
        ),
      if (_devices.isNotEmpty) ...[
        const Divider(height: 24),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text('Your phones & browsers', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
        ),
        for (final d in _devices)
          ExpansionTile(
            initiallyExpanded: d['current'] == true,
            leading: Icon(d['type'] == 'web' ? Icons.computer_rounded : Icons.smartphone_rounded, size: 22, color: AppColors.textSecondary),
            title: Text(_deviceLabel(d), style: const TextStyle(fontSize: 14)),
            children: [
              for (final g in _groups)
                ListTile(
                  dense: true,
                  title: Text(g.$2, style: const TextStyle(fontSize: 13)),
                  trailing: _picker(_modesOf(d['modes'])[g.$1], (v) => _setDevice(d, g.$1, v), inherit: true),
                ),
              if (d['current'] != true)
                TextButton(
                  onPressed: () async {
                    try {
                      await Api.delete('/notification-preferences/devices/${d['id']}');
                      _load();
                    } catch (e) {
                      _toast(apiErrorMessage(e));
                    }
                  },
                  child: const Text('Stop notifications on this device', style: TextStyle(color: AppColors.error)),
                ),
            ],
          ),
      ],
      const Divider(height: 24),
    ]);
  }
}
