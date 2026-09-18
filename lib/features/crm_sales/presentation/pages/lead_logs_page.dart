// ignore_for_file: use_build_context_synchronously
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:go_router/go_router.dart";
import "package:unichat_mobile_app/features/modules/module_providers.dart";
import "package:unichat_mobile_app/features/modules/_shared.dart";
import "package:unichat_mobile_app/features/leads/lead_stage.dart";

// ══════════════════════════ Lead Logs ══════════════════════════

const _leadEvents = [
  'note_added', 'stage_changed', 'assigned', 'reassigned_bulk',
  'lead_assigned', 'lead_assignment_accepted', 'lead_assignment_declined',
  'lead_assignment_timeout', 'lead_assignment_transferred',
  'lead_assignment_completed', 'lead_ai_handoff', 'lead_sla_breached',
];

String _eventLabel(String e) => e.split('_').map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}').join(' ');

class LeadLogsPage extends StatefulWidget {
  const LeadLogsPage({super.key});
  @override
  State<LeadLogsPage> createState() => _LeadLogsPageState();
}

class _LeadLogsPageState extends State<LeadLogsPage> {
  List<Rec> _logs = [];
  bool _loading = true;
  String? _event;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rows = await Api.list('/leads/logs', query: {
        'per_page': 50,
        if (_event != null) 'event': _event,
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
      appBar: AppBar(title: const Text('Lead Activity Logs')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: DropdownButtonFormField<String?>(
              initialValue: _event,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Filter by event', isDense: true),
              items: [
                const DropdownMenuItem(value: null, child: Text('All events')),
                for (final e in _leadEvents) DropdownMenuItem(value: e, child: Text(_eventLabel(e))),
              ],
              onChanged: (v) {
                setState(() => _event = v);
                _load();
              },
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _logs.isEmpty
                    ? Center(child: Text('No activity', style: TextStyle(color: context.mutedColor)))
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.separated(
                          padding: const EdgeInsets.all(12),
                          itemCount: _logs.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (_, i) {
                            final log = _logs[i];
                            final lead = (log['lead'] is Map) ? (log['lead'] as Map) : null;
                            final contact = (lead?['contact'] is Map) ? (lead!['contact'] as Map) : null;
                            final payload = (log['payload'] is Map) ? (log['payload'] as Map) : const {};
                            return RecordCard(
                              title: _eventLabel(str(log['event'], 'event')),
                              subtitle: [
                                if (contact?['name'] != null) contact!['name'],
                                if (payload['from'] != null && payload['to'] != null) '${payload['from']} → ${payload['to']}',
                                str(log['user'], 'System'),
                                when(log['created_at']),
                              ].join(' · '),
                              leadingIcon: Icons.history_rounded,
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

