// ignore_for_file: use_build_context_synchronously
import "package:flutter/material.dart";
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
        'channel': 'meta', // this is the WA Cloud (Meta) log, same as the web's locked channel
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
                  ChoiceChip(label: const Text('Failed'), selected: _status == 'failed',
                      onSelected: (v) { setState(() => _status = v ? 'failed' : null); _load(); }),
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
                              onTap: () => _detail(log),
                              footer: _failureLine(log),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  /// Why a failed message failed — the reason Meta reported (saved on the log by the status webhook).
  Widget? _failureLine(Rec log) {
    if (str(log['status'], '') != 'failed') return null;
    final reason = str(log['failure_reason'], 'No reason was reported by WhatsApp');
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text('Failed: $reason',
          maxLines: 2, overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: AppPalette.danger, fontSize: 12)),
    );
  }

  void _detail(Rec log) {
    final contact = (log['contact'] is Map) ? (log['contact'] as Map) : const {};
    final failed = str(log['status'], '') == 'failed';
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(str(contact['name'] ?? log['phone'], 'Message'),
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              KvRow('Status', str(log['status'])),
              KvRow('Direction', str(log['direction'])),
              KvRow('Type', str(log['type'])),
              KvRow('Phone', str(log['phone'])),
              KvRow('Source', str(log['source'])),
              KvRow('Reference', str(log['reference_name'])),
              KvRow('Category', str(log['category'])),
              KvRow('Sent at', str(log['sent_at'])),
              KvRow('Delivered', str(log['delivered_at'])),
              KvRow('Read', str(log['read_at'])),
              if (str(log['retry_after'], '').isNotEmpty) KvRow('Retry from', str(log['retry_after'])),
              if (failed) ...[
                const SizedBox(height: 8),
                const Text('Failure reason', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(str(log['failure_reason'], 'No reason was reported by WhatsApp'),
                    style: const TextStyle(color: AppPalette.danger)),
              ],
              if (str(log['content'], '').isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text('Content', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(str(log['content'])),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
