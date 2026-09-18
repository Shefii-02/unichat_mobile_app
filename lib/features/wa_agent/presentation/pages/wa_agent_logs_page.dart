// WA Agents' "Logs" quick link — mirrors frontend/src/pages/wa-agent/logs/index.tsx.
// Same data as the "Logs" tab already shown inside WA Chat's Automation Rules page
// (both read /wa-agent/automations/logs), but exposed here as its own standalone page
// with server-side pagination, matching the reference's page-based table.
import 'package:flutter/material.dart';
import 'package:unichat_mobile_app/features/modules/_shared.dart';

const _logStatuses = ['success', 'failed', 'skipped'];

class WaAgentLogsPage extends StatefulWidget {
  const WaAgentLogsPage({super.key});
  @override
  State<WaAgentLogsPage> createState() => _WaAgentLogsPageState();
}

class _WaAgentLogsPageState extends State<WaAgentLogsPage> {
  List<Rec> _logs = [];
  bool _loading = true;
  String? _status;
  int _page = 1;
  int _lastPage = 1;
  int _total = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await Api.raw.get('/wa-agent/automations/logs', queryParameters: {
        if (_status != null) 'status': _status,
        'page': _page,
      });
      final body = (res.data as Map).cast<String, dynamic>();
      final logs = body['data'];
      setState(() {
        _logs = logs is List ? logs.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList() : [];
        _lastPage = (body['last_page'] as num?)?.toInt() ?? 1;
        _total = (body['total'] as num?)?.toInt() ?? _logs.length;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Automation Logs')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(children: [
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: const Text('All'),
                  selected: _status == null,
                  onSelected: (_) { setState(() { _status = null; _page = 1; }); _load(); },
                ),
              ),
              for (final s in _logStatuses)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(s[0].toUpperCase() + s.substring(1)),
                    selected: _status == s,
                    onSelected: (_) { setState(() { _status = s; _page = 1; }); _load(); },
                  ),
                ),
            ]),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _logs.isEmpty
                    ? Center(child: Text('No logs found.', style: TextStyle(color: context.mutedColor)))
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.separated(
                          padding: const EdgeInsets.all(12),
                          itemCount: _logs.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (_, i) => _logCard(_logs[i]),
                        ),
                      ),
          ),
          if (_lastPage > 1)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    onPressed: (_page > 1 && !_loading) ? () { setState(() => _page--); _load(); } : null,
                    icon: const Icon(Icons.chevron_left_rounded),
                  ),
                  Text('Page $_page of $_lastPage · $_total total', style: TextStyle(fontSize: 12, color: context.mutedColor)),
                  IconButton(
                    onPressed: (_page < _lastPage && !_loading) ? () { setState(() => _page++); _load(); } : null,
                    icon: const Icon(Icons.chevron_right_rounded),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _logCard(Rec log) {
    final status = str(log['status'], 'skipped');
    final trigger = log['trigger_data'];
    final triggerText = trigger is Map ? str(trigger['text'], '') : '';
    return RecordCard(
      title: str(log['contact_phone']),
      subtitle: [
        str(log['rule_type'], '').replaceAll('_', ' '),
        if (triggerText.isNotEmpty) '"$triggerText"',
        if (str(log['error_message'], '').isNotEmpty) log['error_message'],
        when(log['created_at']),
      ].where((s) => s != null && '$s'.isNotEmpty).join(' · '),
      leadingIcon: Icons.auto_awesome_rounded,
      trailing: StatusPill(status),
    );
  }
}
