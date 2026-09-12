import 'package:flutter/material.dart';
import 'package:unichat_mobile_app/core/constants/app_colors.dart';
import 'package:unichat_mobile_app/core/network/dio_client.dart';
import 'package:unichat_mobile_app/core/widgets/app_empty_state.dart';

class CampaignsPage extends StatefulWidget {
  const CampaignsPage({super.key});
  @override
  State<CampaignsPage> createState() => _CampaignsPageState();
}

class _CampaignsPageState extends State<CampaignsPage> {
  List<dynamic> _campaigns = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await DioClient.laravelDio.get('/campaigns');
      final data = res.data as Map<String, dynamic>;
      if (mounted) setState(() { _campaigns = (data['data'] as List?) ?? []; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Campaigns'), actions: [
        IconButton(icon: const Icon(Icons.add_circle_outline), onPressed: () {}),
      ]),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _campaigns.isEmpty
              ? AppEmptyState(icon: Icons.campaign_outlined, title: 'No campaigns', subtitle: 'Create your first campaign.')
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _campaigns.length,
                    itemBuilder: (_, i) => _campaignCard(_campaigns[i]),
                  ),
                ),
    );
  }

  Widget _campaignCard(Map<String, dynamic> c) {
    final name   = c['name'] as String? ?? 'Campaign';
    final status = c['status'] as String? ?? 'draft';
    final sent   = c['sent_count'] as int? ?? 0;
    final total  = c['total_recipients'] as int? ?? 1;
    final leads  = c['leads_count'] as int? ?? 0;

    final statusColor = switch (status) {
      'running'   => AppColors.success,
      'scheduled' => AppColors.info,
      'completed' => AppColors.textSecondary,
      _           => AppColors.warning,
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('📢', style: TextStyle(fontSize: 18)),
                const SizedBox(width: 8),
                Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: statusColor.withAlpha(20), borderRadius: BorderRadius.circular(10)),
                  child: Text(status.toUpperCase(), style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Sent: $sent · Leads: $leads', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: total > 0 ? sent / total : 0,
                backgroundColor: AppColors.bgGray,
                valueColor: const AlwaysStoppedAnimation(AppColors.primary),
                minHeight: 6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
