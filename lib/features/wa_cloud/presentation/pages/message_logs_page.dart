// ignore_for_file: use_build_context_synchronously
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:unichat_mobile_app/features/modules/module_providers.dart";
import "package:unichat_mobile_app/features/modules/_shared.dart";

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
