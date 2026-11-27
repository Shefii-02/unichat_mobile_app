import 'package:flutter/material.dart';
import 'package:unichat_mobile_app/core/theme/mockup_palette.dart';
import 'package:unichat_mobile_app/features/modules/_shared.dart';
import 'package:unichat_mobile_app/features/wa_cloud/presentation/pages/wa_cloud_inbox_page.dart';
import 'package:unichat_mobile_app/features/workspace_home/ws_style.dart';
import 'package:url_launcher/url_launcher.dart';

/// The Sales dashboard's work lists as horizontal tabs — Hot leads, Today's tasks, Today's follow-ups, Today's installment follow-ups.
/// Each tab loads the latest 10 and a "Load more" button fetches the next 10 (GET /home/sales/feed). Every row has: call, WhatsApp (wa.me),
/// the WA Cloud inbox chat, and a "note / activity" sheet (tapping the row opens that sheet too).
class SalesFeed extends StatefulWidget {
  const SalesFeed({super.key, this.onChanged});

  /// Called after a note / activity was saved, so the dashboard's counters can refresh.
  final VoidCallback? onChanged;

  @override
  State<SalesFeed> createState() => _SalesFeedState();
}

class _TabData {
  List<Map<String, dynamic>> items = [];
  bool loading = false, loaded = false, hasMore = false;
  String? error;
}

class _SalesFeedState extends State<SalesFeed> {
  static const _pageSize = 10;
  static const _tabs = [
    ('hot', 'Hot leads', 'New leads assigned to you will appear here.'),
    ('tasks', "Today's tasks", 'No tasks due today — nice.'),
    ('followups', "Today's follow-ups", 'No follow-ups due today — nice.'),
    ('installments', 'Installment follow-ups', 'No installments to follow up today.'),
  ];

  final _data = {for (final t in _tabs) t.$1: _TabData()};
  String _tab = 'hot';

  @override
  void initState() {
    super.initState();
    _load(_tab);
  }

  Future<void> _load(String tab, {bool more = false}) async {
    final d = _data[tab]!;
    if (d.loading) return;
    setState(() {
      d.loading = true;
      d.error = null;
    });
    try {
      final res = await Api.one('/home/sales/feed', query: {'tab': tab, 'offset': more ? d.items.length : 0, 'limit': _pageSize});
      final rows = asRows(res['items']);
      if (!mounted) return;
      setState(() {
        d.items = more ? [...d.items, ...rows] : rows;
        d.hasMore = res['has_more'] == true;
        d.loaded = true;
      });
    } catch (e) {
      if (mounted) setState(() => d.error = apiErrorMessage(e));
    } finally {
      if (mounted) setState(() => d.loading = false);
    }
  }

  Future<void> _launch(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  String _digits(Object? phone) => '${phone ?? ''}'.replaceAll(RegExp(r'[^0-9]'), '');

  void _toast(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  /// The WA Cloud inbox conversation for this number (the API finds it by phone); a chat only exists once they have messaged / been messaged.
  Future<void> _openInbox(Map<String, dynamic> it) async {
    final phone = _digits(it['phone']);
    if (phone.isEmpty) return _toast('No phone number on this one.');
    try {
      final res = await Api.raw.get('/conversations/contact/0', queryParameters: {'phone': phone});
      final convs = asRows((res.data as Map)['conversations']);
      if (!mounted) return;
      if (convs.isEmpty) return _toast('No WhatsApp inbox chat with ${it['name'] ?? 'this number'} yet.');
      final c = {...convs.first, 'contact_name': it['name']};
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => WaCloudThreadPage(conversation: c)));
    } catch (e) {
      if (mounted) _toast(apiErrorMessage(e));
    }
  }

  /// One sheet for both: a plain note, or a logged call / message / meeting with its outcome and next follow-up.
  Future<void> _addActivity(Map<String, dynamic> it) async {
    final leadId = n(it['lead_id'])?.toInt();
    if (leadId == null) return _toast('This item is not linked to a lead.');
    final data = <String, dynamic>{};
    DateTime? next;
    final ok = await showFormSheet(
      context,
      title: 'Note · ${it['name'] ?? 'Lead'}',
      submitLabel: 'Save',
      fields: (ctx) => [
        FSelect<String>(
          label: 'Type',
          options: const ['note', 'call', 'message', 'meeting', 'visit', 'other'],
          initial: 'note',
          labelOf: (v) => v[0].toUpperCase() + v.substring(1),
          onSaved: (v) => data['kind'] = v ?? 'note',
        ),
        FSelect<String>(label: 'Outcome (for calls / messages)', options: const ['connected', 'not_reachable', 'callback', 'interested', 'not_interested', 'wrong_number'], labelOf: (v) => v.replaceAll('_', ' '), onSaved: (v) { if (v != null) data['outcome'] = v; }),
        FText(label: 'Notes', required: true, maxLines: 4, onSaved: (v) => data['notes'] = v),
        StatefulBuilder(
          builder: (c, set) => OutlinedButton.icon(
            icon: const Icon(Icons.event_rounded),
            label: Text(next == null ? 'Next follow-up (optional)' : 'Follow up ${next.toString().substring(0, 16)}'),
            onPressed: () async {
              final d = await showDatePicker(context: c, initialDate: DateTime.now().add(const Duration(days: 1)), firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 730)));
              if (d == null || !c.mounted) return;
              final t = await showTimePicker(context: c, initialTime: const TimeOfDay(hour: 10, minute: 0));
              if (t == null) return;
              set(() => next = DateTime(d.year, d.month, d.day, t.hour, t.minute));
            },
          ),
        ),
      ],
      onSubmit: () async {
        final notes = '${data['notes']}';
        if (data['kind'] == 'note') {
          await Api.post('/leads/$leadId/notes', data: {'content': notes});
          // a note can still carry the next follow-up date
          if (next != null) await Api.post('/leads/$leadId/activities', data: {'kind': 'other', 'notes': notes, 'next_follow_up_at': next!.toIso8601String()});
        } else {
          await Api.post('/leads/$leadId/activities', data: {...data, if (next != null) 'next_follow_up_at': next!.toIso8601String()});
        }
      },
    );
    if (ok) {
      _toast('Saved.');
      widget.onChanged?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _data[_tab]!;
    final empty = _tabs.firstWhere((t) => t.$1 == _tab).$3;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          height: 36,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _tabs.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final t = _tabs[i];
              final on = t.$1 == _tab;
              return ChoiceChip(
                label: Text(t.$2, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: on ? Colors.white : null)),
                selected: on,
                showCheckmark: false,
                selectedColor: M.lavenderMuted,
                onSelected: (_) {
                  setState(() => _tab = t.$1);
                  if (!_data[t.$1]!.loaded) _load(t.$1);
                },
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        if (d.error != null && d.items.isEmpty)
          WsLoadError(d.error, () => _load(_tab))
        else if (!d.loaded)
          const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
        else
          WsRows([for (final it in d.items) _row(it)], empty: empty),
        if (d.loaded && d.hasMore)
          Align(
            alignment: Alignment.center,
            child: TextButton(
              onPressed: d.loading ? null : () => _load(_tab, more: true),
              child: d.loading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Load more'),
            ),
          ),
      ]),
    );
  }

  Widget _row(Map<String, dynamic> it) {
    final phone = _digits(it['phone']);
    final overdue = it['overdue'] == true;
    final at = '${it['at'] ?? ''}';
    final sub = [
      '${it['subtitle'] ?? ''}',
      if (_tab == 'hot') (at.isEmpty ? '' : '${wsAgo(at)} ago') else if (overdue) 'overdue' else if (at.contains(':') && at.length > 10) wsClock(at),
    ].where((s) => s.isNotEmpty).join(' · ');
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      WsRow(
        leading: WsAvatar('${it['name'] ?? ''}'),
        title: '${_tab == 'hot' || _tab == 'installments' ? it['name'] ?? '' : it['title'] ?? ''}',
        subtitle: sub,
        trailing: overdue ? const WsBadge('Overdue', tintRed) : null,
        onTap: () => _addActivity(it),
      ),
      const SizedBox(height: 8),
      Row(children: [
        const SizedBox(width: 48),
        WsIconBtn(Icons.phone_outlined, phone.isEmpty ? () => _toast('No phone number on this one.') : () => _launch('tel:${it['phone']}')),
        const SizedBox(width: 8),
        WsIconBtn(Icons.chat_rounded, phone.isEmpty ? () => _toast('No phone number on this one.') : () => _launch('https://wa.me/$phone'), fg: Colors.white, bg: M.taskDoneBg),
        const SizedBox(width: 8),
        WsIconBtn(Icons.forum_outlined, () => _openInbox(it)),
        const SizedBox(width: 8),
        WsIconBtn(Icons.edit_note_rounded, () => _addActivity(it)),
      ]),
    ]);
  }
}
