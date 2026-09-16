// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'module_providers.dart';
import '_shared.dart';

// ══════════════════════════ Settings (Meta credentials) ══════════════════════════

class WaCloudSettingsPage extends ConsumerWidget {
  const WaCloudSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('WA Cloud Settings')),
      body: ProviderObject(
        provider: waCloudSettingsProvider,
        builder: (context, c) {
          final connected = c['wa_connected'] == true;
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: context.altSurface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: context.lineColor),
                ),
                child: Row(children: [
                  Icon(connected ? Icons.check_circle_rounded : Icons.cancel_rounded,
                      color: connected ? AppPalette.success : AppPalette.danger),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(connected ? 'Connected to Meta Cloud API' : 'Not connected',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ]),
              ),
              const SizedBox(height: 16),
              KvRow('Phone number ID', str(c['wa_phone_id'])),
              KvRow('Business account ID', str(c['wa_business_id'])),
              KvRow('Access token', c['wa_access_token'] != null && '${c['wa_access_token']}'.isNotEmpty ? '•••••••• (set)' : 'Not set'),
              const SizedBox(height: 20),
              Wrap(spacing: 8, runSpacing: 8, children: [
                FilledButton.icon(
                  onPressed: () => _editCredentials(context, ref, c),
                  icon: const Icon(Icons.edit_rounded, size: 18),
                  label: const Text('Edit credentials'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _verify(context, ref),
                  icon: const Icon(Icons.wifi_tethering_rounded, size: 18),
                  label: const Text('Verify connection'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _testSend(context),
                  icon: const Icon(Icons.send_rounded, size: 18),
                  label: const Text('Test send'),
                ),
              ]),
            ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _editCredentials(BuildContext context, WidgetRef ref, Rec c) async {
    final data = <String, dynamic>{};
    final ok = await showFormSheet(
      context,
      title: 'Meta Cloud API credentials',
      fields: (ctx) => [
        FText(label: 'Phone number ID', initial: c['wa_phone_id'] as String?, required: true,
            onSaved: (v) => data['wa_phone_id'] = v),
        FText(label: 'Access token', required: true, maxLines: 3,
            hint: 'Paste the permanent or long-lived Meta access token',
            onSaved: (v) => data['wa_access_token'] = v),
        FText(label: 'Business account ID', initial: c['wa_business_id'] as String?,
            onSaved: (v) => v.isEmpty ? null : data['wa_business_id'] = v),
      ],
      onSubmit: () => Api.post('/settings/wa-credentials', data: data),
    );
    if (ok) ref.invalidate(waCloudSettingsProvider);
  }

  Future<void> _verify(BuildContext context, WidgetRef ref) async {
    try {
      final res = await Api.one('/settings/verify-wa');
      if (!context.mounted) return;
      final ok = res['connected'] == true;
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(ok ? 'Connected' : 'Not connected'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: ok
                ? [
                    KvRow('Phone number', str(res['phone_number'])),
                    KvRow('Verified name', str(res['verified_name'])),
                    KvRow('Quality rating', str(res['quality_rating'])),
                    KvRow('Messaging tier', str(res['messaging_limit_tier'])),
                  ]
                : [Text(str(res['error'], 'Could not verify credentials.'))],
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
        ),
      );
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
    }
  }

  Future<void> _testSend(BuildContext context) async {
    final data = <String, dynamic>{};
    await showFormSheet(
      context,
      title: 'Send a test message',
      submitLabel: 'Send',
      fields: (ctx) => [
        FText(label: 'Phone number (digits only, with country code)', required: true,
            keyboardType: TextInputType.phone, onSaved: (v) => data['phone'] = v),
        FText(label: 'Message', maxLines: 3, onSaved: (v) => v.isEmpty ? null : data['message'] = v),
      ],
      onSubmit: () => Api.post('/settings/test-send', data: data),
    );
  }
}

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

// ══════════════════════════ Message Logs ══════════════════════════

class MessageLogsPage extends StatefulWidget {
  const MessageLogsPage({super.key});
  @override
  State<MessageLogsPage> createState() => _MessageLogsPageState();
}

class _MessageLogsPageState extends State<MessageLogsPage> {
  List<Rec> _logs = [];
  bool _loading = true;
  String? _direction;
  String? _status;
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rows = await Api.list('/message-logs', query: {
        'per_page': 100,
        if (_direction != null) 'direction': _direction,
        if (_status != null) 'status': _status,
        if (_search.text.isNotEmpty) 'search': _search.text,
      });
      setState(() {
        _logs = rows;
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Message Logs')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: TextField(
              controller: _search,
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Search phone, contact or content…',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
              ),
              onSubmitted: (_) => _load(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(children: [
              Expanded(
                child: Wrap(spacing: 6, children: [
                  ChoiceChip(label: const Text('All'), selected: _direction == null,
                      onSelected: (_) { setState(() => _direction = null); _load(); }),
                  ChoiceChip(label: const Text('Inbound'), selected: _direction == 'inbound',
                      onSelected: (_) { setState(() => _direction = 'inbound'); _load(); }),
                  ChoiceChip(label: const Text('Outbound'), selected: _direction == 'outbound',
                      onSelected: (_) { setState(() => _direction = 'outbound'); _load(); }),
                ]),
              ),
            ]),
          ),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _logs.isEmpty
                    ? Center(child: Text('No messages logged', style: TextStyle(color: context.mutedColor)))
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.separated(
                          padding: const EdgeInsets.all(12),
                          itemCount: _logs.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (_, i) {
                            final log = _logs[i];
                            final contact = (log['contact'] is Map) ? (log['contact'] as Map) : const {};
                            final inbound = log['direction'] == 'inbound';
                            return RecordCard(
                              title: str(contact['name'] ?? log['phone'], 'Unknown'),
                              subtitle: '${str(log['type'], 'text')} · ${str(log['phone'])} · ${when(log['created_at'])}',
                              leadingIcon: inbound ? Icons.call_received_rounded : Icons.call_made_rounded,
                              leadingColor: inbound ? AppPalette.info : AppPalette.accent,
                              trailing: StatusPill(str(log['status'], 'sent')),
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
