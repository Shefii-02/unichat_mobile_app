import 'package:flutter/material.dart';
import 'package:unichat_mobile_app/core/constants/app_colors.dart';
import 'package:unichat_mobile_app/core/network/dio_client.dart';
import 'package:unichat_mobile_app/core/utils/format_utils.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});
  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  List<dynamic> _notifications = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await DioClient.laravelDio.get('/notifications');
      final data = res.data as Map<String, dynamic>;
      if (mounted) setState(() { _notifications = (data['data'] as List?) ?? []; _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _notifications = []; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications'), actions: [
        IconButton(icon: const Icon(Icons.done_all), onPressed: () {}, tooltip: 'Mark all read'),
      ]),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _notifications.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('🔔', style: TextStyle(fontSize: 48)),
                      SizedBox(height: 12),
                      Text('No notifications', style: TextStyle(color: AppColors.textLight, fontSize: 16)),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    itemCount: _notifications.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final n    = _notifications[i];
                      final type = n['type'] as String? ?? '';
                      final msg  = n['message'] as String? ?? '';
                      final ts   = n['created_at'] != null ? DateTime.tryParse(n['created_at'] as String) : null;
                      final read = n['read_at'] != null;

                      return ListTile(
                        leading: Text(_iconFor(type), style: const TextStyle(fontSize: 26)),
                        title: Text(msg, style: TextStyle(fontWeight: read ? FontWeight.normal : FontWeight.w700)),
                        subtitle: Text(FormatUtils.relative(ts)),
                        tileColor: read ? null : AppColors.primary.withAlpha(8),
                        onTap: () {},
                      );
                    },
                  ),
                ),
    );
  }

  String _iconFor(String type) {
    return switch (type) {
      'new_lead'       => '🔔',
      'ai_offer'       => '🤖',
      'sla_breach'     => '⏰',
      'lead_converted' => '✅',
      'campaign_done'  => '📢',
      _                => '💬',
    };
  }
}
