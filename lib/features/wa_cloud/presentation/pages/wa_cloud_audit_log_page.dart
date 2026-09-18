// ignore_for_file: use_build_context_synchronously
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:unichat_mobile_app/features/modules/module_providers.dart";
import "package:unichat_mobile_app/features/modules/_shared.dart";

// ══════════════════════════ Audit Logs (webhook delivery log) ══════════════════════════

const _webhookStatuses = ['received', 'processed', 'failed', 'error'];

class WaCloudAuditLogPage extends StatefulWidget {
  const WaCloudAuditLogPage({super.key});
  @override
  State<WaCloudAuditLogPage> createState() => _WaCloudAuditLogPageState();
}

class _WaCloudAuditLogPageState extends State<WaCloudAuditLogPage> {
  List<Rec> _logs = [];
  bool _loading = true;
  String? _status;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await Api.one('/settings/webhook-logs', query: {
        'limit': 150,
        if (_status != null) 'status': _status,
      });
      final logs = res['logs'];
      setState(() {
        _logs = logs is List ? logs.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList() : [];
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('WA Cloud Audit Log')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(label: const Text('All'), selected: _status == null,
                      onSelected: (_) { setState(() => _status = null); _load(); }),
                ),
                for (final s in _webhookStatuses)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(label: Text(s), selected: _status == s,
                        onSelected: (_) { setState(() => _status = s); _load(); }),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _logs.isEmpty
                    ? Center(child: Text('No webhook events', style: TextStyle(color: context.mutedColor)))
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.separated(
                          padding: const EdgeInsets.all(12),
                          itemCount: _logs.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (_, i) {
                            final log = _logs[i];
                            return RecordCard(
                              title: str(log['event_type'], 'webhook'),
                              subtitle: [
                                str(log['detail'], ''),
                                if (log['phone'] != null) log['phone'],
                                if (log['error'] != null) log['error'],
                                if (log['ms'] != null) '${log['ms']}ms',
                                when(log['created_at']),
                              ].where((s) => s != null && '$s'.isNotEmpty).join(' · '),
                              leadingIcon: Icons.webhook_rounded,
                              trailing: StatusPill(str(log['status'], 'received')),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

