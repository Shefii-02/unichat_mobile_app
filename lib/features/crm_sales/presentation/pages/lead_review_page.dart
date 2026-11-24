// ignore_for_file: use_build_context_synchronously
import "package:flutter/material.dart";
import "package:unichat_mobile_app/core/permissions/permission_guard.dart";
import "package:unichat_mobile_app/features/modules/_shared.dart";

// ══════════════════ Lead review (contacts waiting for a check) ══════════════════

const _topicLabel = {
  'lead_enquiry': 'Lead enquiry',
  'technical': 'Technical / support',
  'billing': 'Billing',
  'complaint': 'Complaint',
  'existing_customer': 'Existing customer',
  'other': 'Other conversation',
};

const _sourceLabel = {
  'wa_chat': 'WA Chat',
  'whatsapp_cloud': 'WhatsApp Cloud',
  'instagram': 'Instagram',
  'website': 'Website widget',
  'meta_ads': 'Meta Ads',
  'flow': 'Flow',
};

/// New contacts waiting for a team head's check (or held because their source is off). One tap moves a real one into
/// Leads — optionally to a chosen staff member — and the rest can be discarded. Backed by /leads/held.
class LeadReviewPage extends StatefulWidget {
  const LeadReviewPage({super.key});
  @override
  State<LeadReviewPage> createState() => _LeadReviewPageState();
}

class _LeadReviewPageState extends State<LeadReviewPage> {
  List<Rec> _rows = [];
  List<Rec> _staff = [];
  bool _loading = true;
  String _reason = 'needs_review'; // needs_review | all
  int _waiting = 0;
  final Set<int> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
    _loadStaff();
  }

  Future<void> _loadStaff() async {
    if (!PermissionGuard.can('staff.view')) return;
    try {
      final s = await Api.list('/staff', query: {'per_page': 200});
      if (mounted) setState(() => _staff = s.where((x) => x['is_active'] != false).toList());
    } catch (_) {}
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await Api.raw.get('/leads/held', queryParameters: {
        'status': 'held',
        'per_page': 50,
        if (_reason != 'all') 'reason': _reason,
      });
      final d = res.data as Map<String, dynamic>;
      setState(() {
        _rows = ((d['data'] as List?) ?? const []).whereType<Map<String, dynamic>>().toList();
        _waiting = ((d['summary'] as Map?)?['held'] as num?)?.toInt() ?? _rows.length;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
      }
    }
  }

  Future<void> _act(Rec r, String kind, {int? assignTo}) async {
    final id = (r['id'] as num).toInt();
    setState(() => _busy.add(id));
    try {
      final res = await Api.post('/leads/held/$kind', data: {'ids': [id], if (assignTo != null) 'assign_to': assignTo});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${res['message'] ?? 'Done'}')));
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  /// "Move to Leads": automatic assignment by default, or pick who gets it.
  Future<void> _moveSheet(Rec r) async {
    final name = str((r['contact'] as Map?)?['name'], str((r['contact'] as Map?)?['phone'], 'this contact'));
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(title: Text('Move $name to Leads', style: const TextStyle(fontWeight: FontWeight.w700)), subtitle: const Text('Who should get this lead?')),
            ListTile(
              leading: const Icon(Icons.auto_awesome_rounded),
              title: const Text('Automatic (normal assignment)'),
              onTap: () { Navigator.pop(ctx); _act(r, 'move'); },
            ),
            Flexible(
              child: ListView(shrinkWrap: true, children: [
                for (final s in _staff)
                  ListTile(
                    leading: const Icon(Icons.person_outline_rounded),
                    title: Text(str(s['name'])),
                    onTap: () { Navigator.pop(ctx); _act(r, 'move', assignTo: (s['id'] as num).toInt()); },
                  ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!PermissionGuard.can('leads.manage')) {
      return Scaffold(appBar: AppBar(title: const Text('Lead review')), body: Center(child: Text("You don't have access to this section", style: TextStyle(color: context.mutedColor))));
    }
    return Scaffold(
      appBar: AppBar(title: Text('Lead review${_waiting > 0 ? ' ($_waiting)' : ''}')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(children: [
            ChoiceChip(label: const Text('Needs a check'), selected: _reason == 'needs_review', onSelected: (_) { setState(() => _reason = 'needs_review'); _load(); }),
            const SizedBox(width: 8),
            ChoiceChip(label: const Text('Everything waiting'), selected: _reason == 'all', onSelected: (_) { setState(() => _reason = 'all'); _load(); }),
          ]),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _rows.isEmpty
                  ? Center(child: Text('Nothing is waiting', style: TextStyle(color: context.mutedColor)))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: _rows.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) => _card(_rows[i]),
                      ),
                    ),
        ),
      ]),
    );
  }

  Widget _card(Rec r) {
    final c = (r['contact'] as Map?) ?? const {};
    final id = (r['id'] as num).toInt();
    final topic = r['topic'] as String?;
    final conf = (r['topic_confidence'] as num?)?.toDouble();
    final sample = r['sample_text'] as String? ?? r['notes'] as String?;
    final isLead = topic == 'lead_enquiry';
    final busy = _busy.contains(id);
    final quoted = sample != null && sample.isNotEmpty && !RegExp(r'^[\u{1F300}-\u{1FAFF}\u{1F000}-\u{1F2FF}(]', unicode: true).hasMatch(sample);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(str(c['name'], str(c['phone'])), style: const TextStyle(fontWeight: FontWeight.w700))),
            Text(_sourceLabel[r['source']] ?? str(r['source']), style: TextStyle(fontSize: 11, color: context.mutedColor)),
          ]),
          if (c['phone'] != null) Text('${c['phone']}', style: TextStyle(fontSize: 12, color: context.mutedColor)),
          if (topic != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: (isLead ? Colors.green : Colors.amber).withValues(alpha: 0.18), borderRadius: BorderRadius.circular(99)),
                child: Text('${_topicLabel[topic] ?? topic}${conf != null ? ' · ${(conf * 100).round()}%' : ''}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: isLead ? Colors.green.shade800 : Colors.amber.shade900)),
              ),
            ),
          if (sample != null && sample.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(quoted ? '“$sample”' : sample, maxLines: 3, overflow: TextOverflow.ellipsis)),
          const SizedBox(height: 8),
          Row(children: [
            FilledButton.icon(
              onPressed: busy ? null : () => (_staff.isEmpty ? _act(r, 'move') : _moveSheet(r)),
              icon: const Icon(Icons.arrow_forward_rounded, size: 16),
              label: const Text('Move to Leads'),
            ),
            const SizedBox(width: 8),
            TextButton(onPressed: busy ? null : () => _act(r, 'discard'), child: const Text('Discard')),
            const Spacer(),
            if (busy) const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          ]),
        ]),
      ),
    );
  }
}
