import 'package:flutter/material.dart';
import 'package:unichat_mobile_app/core/constants/app_colors.dart';
import 'package:unichat_mobile_app/core/network/dio_client.dart';
import 'package:unichat_mobile_app/core/utils/format_utils.dart';
import 'package:unichat_mobile_app/core/widgets/app_avatar.dart';
import 'package:unichat_mobile_app/core/widgets/app_button.dart';
import 'package:unichat_mobile_app/core/widgets/lead_score_badge.dart';
import 'package:url_launcher/url_launcher.dart';

class LeadDetailPage extends StatefulWidget {
  const LeadDetailPage({super.key, required this.id});
  final int id;
  @override
  State<LeadDetailPage> createState() => _LeadDetailPageState();
}

class _LeadDetailPageState extends State<LeadDetailPage> with SingleTickerProviderStateMixin {
  late TabController _tabs;
  Map<String, dynamic>? _lead;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await DioClient.laravelDio.get('/leads/${widget.id}');
      setState(() { _lead = (res.data as Map<String, dynamic>)['data'] as Map<String, dynamic>?; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _accept() async {
    try {
      await DioClient.laravelDio.post('/leads/${widget.id}/accept');
      _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Lead accepted!')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _complete() async {
    try {
      await DioClient.laravelDio.post('/leads/${widget.id}/complete');
      _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Lead converted!')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  @override
  void dispose() { _tabs.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final contact = _lead?['contact'] as Map<String, dynamic>?;
    final name    = contact?['name'] as String? ?? 'Unknown';
    final score   = _lead?['lead_score'] as int? ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Text(name),
            const SizedBox(width: 8),
            LeadScoreBadge(score: score),
          ],
        ),
        bottom: TabBar(
          controller: _tabs,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          indicatorColor: AppColors.primaryLight,
          tabs: const [Tab(text: 'Overview'), Tab(text: 'Timeline'), Tab(text: 'Chats'), Tab(text: 'Notes')],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _lead == null
              ? const Center(child: Text('Lead not found'))
              : TabBarView(
                  controller: _tabs,
                  children: [_overview(), _timeline(), _chats(), _notes()],
                ),
    );
  }

  Widget _overview() {
    final contact  = _lead?['contact'] as Map<String, dynamic>?;
    final staff    = _lead?['staff']   as Map<String, dynamic>?;
    final campaign = _lead?['campaign'] as Map<String, dynamic>?;
    final name     = contact?['name'] as String? ?? 'Unknown';
    final phone    = contact?['phone'] as String? ?? '';
    final score    = _lead?['lead_score'] as int? ?? 0;
    final status   = _lead?['status'] as String? ?? '';
    final sla      = _lead?['sla_breached'] as bool? ?? false;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Score card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      LeadScoreBadge(score: score, large: true),
                      const SizedBox(width: 12),
                      Text(FormatUtils.scoreLabel(score), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
                      const Spacer(),
                      if (sla)
                        const Text('⏰ SLA Breached', style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w700)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  LinearProgressIndicator(
                    value: score / 100,
                    backgroundColor: AppColors.bgGray,
                    valueColor: AlwaysStoppedAnimation(AppColors.scoreColor(score)),
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Contact info
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      AppAvatar(name: name, size: 50),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                          Text(FormatUtils.phone(phone), style: const TextStyle(color: AppColors.textSecondary)),
                          if (staff != null)
                            Text('👤 ${staff['name']}', style: const TextStyle(color: AppColors.textLight, fontSize: 12)),
                        ],
                      ),
                    ],
                  ),
                  if (campaign != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: AppColors.info.withAlpha(15), borderRadius: BorderRadius.circular(8)),
                      child: Row(
                        children: [
                          const Text('📢', style: TextStyle(fontSize: 16)),
                          const SizedBox(width: 8),
                          Text(campaign['name'] as String? ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Actions
          Row(
            children: [
              Expanded(child: AppButton(label: '💬 Chat', onPressed: () {}, variant: AppButtonVariant.secondary, small: true)),
              const SizedBox(width: 8),
              Expanded(child: AppButton(label: '📞 WA Call', onPressed: () => _waCall(phone), variant: AppButtonVariant.secondary, small: true)),
              const SizedBox(width: 8),
              Expanded(child: AppButton(label: '✅ Convert', onPressed: _complete, variant: AppButtonVariant.primary, small: true)),
            ],
          ),
          const SizedBox(height: 8),
          AppButton(label: 'Accept Lead', onPressed: _accept, expand: true),
        ],
      ),
    );
  }

  Widget _timeline() {
    final events = [
      ('🔔', 'Lead assigned', _lead?['created_at']),
      ('📊', 'Score updated', null),
    ];
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: events.length,
      itemBuilder: (_, i) {
        final e = events[i];
        return ListTile(
          leading: Text(e.$1, style: const TextStyle(fontSize: 22)),
          title: Text(e.$2),
          subtitle: e.$3 != null ? Text(FormatUtils.relative(DateTime.tryParse(e.$3 as String))) : null,
        );
      },
    );
  }

  Widget _chats() => const Center(child: Text('Chat history coming soon', style: TextStyle(color: AppColors.textLight)));

  Widget _notes() => const Center(child: Text('Notes coming soon', style: TextStyle(color: AppColors.textLight)));

  void _waCall(String phone) {
    final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    launchUrl(Uri.parse('https://wa.me/$digits?call=1'));
  }
}
