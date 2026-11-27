// The lead page's tabs — the same set as the web lead page: Contact & pipeline · Lead information · Chat · Referred by · Assigned staff ·
// Category & labels · Campaigns (+ Installments, which lives in lead_installments.dart).
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:unichat_mobile_app/features/leads/lead_stage.dart';
import 'package:unichat_mobile_app/core/utils/message_label.dart';
import 'package:unichat_mobile_app/features/modules/_shared.dart';
import 'package:unichat_mobile_app/features/wa_cloud/presentation/pages/wa_cloud_inbox_page.dart';

/// The round, border-only pills the web uses for inner tabs: the open one is outlined and bold, never filled.
class OutlinePills extends StatelessWidget {
  const OutlinePills({super.key, required this.labels, required this.index, required this.onChanged});
  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;
  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return SizedBox(
      height: 40,
      child: ListView(scrollDirection: Axis.horizontal, children: [
        for (var i = 0; i < labels.length; i++)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(labels[i], style: TextStyle(fontSize: 12.5, fontWeight: i == index ? FontWeight.w700 : FontWeight.w500)),
              selected: i == index,
              showCheckmark: false,
              backgroundColor: Colors.transparent,
              selectedColor: Colors.transparent,
              side: BorderSide(color: i == index ? primary : context.lineColor, width: i == index ? 1.6 : 1),
              onSelected: (_) => onChanged(i),
            ),
          ),
      ]),
    );
  }
}

/// "Contact & pipeline": three inner tabs so the first tab isn't one long page — contact + pipeline, the call form, the activity feed.
class LeadMainTab extends StatefulWidget {
  const LeadMainTab({super.key, required this.main, required this.call, required this.activity, this.activityCount = 0, this.onRefresh});
  final Widget main, call, activity;
  final int activityCount;
  final Future<void> Function()? onRefresh;
  @override
  State<LeadMainTab> createState() => _LeadMainTabState();
}

class _LeadMainTabState extends State<LeadMainTab> {
  int _i = 0;
  @override
  Widget build(BuildContext context) {
    final body = [widget.main, widget.call, widget.activity][_i];
    final list = ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        OutlinePills(
          labels: ['👤 Contact & pipeline', '📞 Log a call', widget.activityCount > 0 ? '📝 Activities (${widget.activityCount})' : '📝 Activities'],
          index: _i,
          onChanged: (v) => setState(() => _i = v),
        ),
        const SizedBox(height: 14),
        body,
      ],
    );
    return widget.onRefresh == null ? list : RefreshIndicator(onRefresh: widget.onRefresh!, child: list);
  }
}

Widget _card(BuildContext context, {required String title, Widget? trailing, required List<Widget> children}) => Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: context.lineColor)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14))), if (trailing != null) trailing]),
        const SizedBox(height: 10),
        ...children,
      ]),
    );

Widget _kv(BuildContext context, String k, String v) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 116, child: Text(k, style: TextStyle(color: context.mutedColor, fontSize: 12.5))),
        Expanded(child: Text(v.isEmpty ? '—' : v, style: const TextStyle(fontSize: 13.5))),
      ]),
    );

/// Contact details + the four contact actions (call · IVR · WA Chat · WA shared inbox).
class LeadContactCard extends StatelessWidget {
  const LeadContactCard({super.key, required this.leadId, required this.lead});
  final int leadId;
  final Rec lead;

  @override
  Widget build(BuildContext context) {
    final c = lead['contact'] is Map ? (lead['contact'] as Map).cast<String, dynamic>() : <String, dynamic>{};
    final phone = str(c['phone']);
    final hidden = c['phone_is_real'] == false;   // a WhatsApp privacy id, not a dialable number
    final digits = phone.replaceAll(RegExp(r'\D'), '');

    Widget action(String label, IconData icon, VoidCallback? onTap, {Color? color}) => Expanded(
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: OutlinedButton.icon(
              onPressed: onTap,
              icon: Icon(icon, size: 17, color: onTap == null ? null : color),
              label: Text(label, style: const TextStyle(fontSize: 11.5), maxLines: 1, overflow: TextOverflow.ellipsis),
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10), side: BorderSide(color: onTap == null ? context.lineColor : (color ?? context.lineColor))),
            ),
          ),
        );

    return _card(context, title: 'Contact details', children: [
      _kv(context, 'Name', str(c['name'])),
      _kv(context, 'Phone', phone),
      _kv(context, 'Email', str(c['email'])),
      if (phone.isNotEmpty) ...[
        const SizedBox(height: 6),
        if (hidden)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: const Color(0xFFFEF3C7), borderRadius: BorderRadius.circular(10)),
            child: const Text("WhatsApp is hiding this customer's real number, so calling and the shared inbox can't work yet. Chat with them in WA Chat.", style: TextStyle(fontSize: 12, color: Color(0xFF92400E))),
          ),
        Row(children: [
          action('Phone call', Icons.call_rounded, hidden ? null : () => launchUrl(Uri.parse('tel:+$digits'))   // only dials — logging the call is its own step (Log a call tab)
, color: const Color(0xFF16A34A)),
          action('IVR call', Icons.dialpad_rounded, null),
        ]),
        Row(children: [
          action('WA Chat', Icons.chat_rounded, () => showLeadWaChat(context, leadId, str(c['name'], phone)), color: const Color(0xFF25D366)),
          action('WA shared inbox', Icons.inbox_rounded, hidden ? null : () => openLeadInbox(context, c), color: const Color(0xFF2563EB)),
        ]),
      ],
    ]);
  }
}

/// The contact's WA Cloud chat (one per number) — opens the thread, which has the 24-hour free-text / template rules built in.
Future<void> openLeadInbox(BuildContext context, Map<String, dynamic> contact) async {
  try {
    final r = await Api.raw.get('/conversations/contact/${contact['id'] ?? 0}', queryParameters: {'phone': '${contact['phone'] ?? ''}'});
    final convs = ((r.data as Map)['conversations'] as List? ?? const []).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
    if (!context.mounted) return;
    if (convs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No WA Cloud chat with this customer yet. Start one from the WA Cloud inbox with a template.')));
      return;
    }
    Rec pick = convs.first;
    if (convs.length > 1) {
      final chosen = await showModalBottomSheet<Rec>(
        context: context,
        builder: (ctx) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Padding(padding: EdgeInsets.all(16), child: Text('Choose a chat', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
            for (final c in convs) ListTile(title: Text('via ${c['number'] ?? c['phone']}'), subtitle: Text('${c['status']} · ${when(c['last_message_at'])}'), onTap: () => Navigator.pop(ctx, c)),
          ]),
        ),
      );
      if (chosen == null || !context.mounted) return;
      pick = chosen;
    }
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => WaCloudThreadPage(conversation: pick)));
  } catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
  }
}

/// The lead's WhatsApp Chat (open-wa) thread with a reply box. It goes through our own server (`/leads/{id}/wa-chat`), which talks to the
/// chat gateway itself — the phone never calls the gateway's public address, so it keeps working when that address is unreachable.
Future<void> showLeadWaChat(BuildContext context, int leadId, String title) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    builder: (_) => _WaChatSheet(leadId: leadId, title: title),
  );
}

class _WaChatSheet extends StatefulWidget {
  const _WaChatSheet({required this.leadId, required this.title});
  final int leadId;
  final String title;
  @override
  State<_WaChatSheet> createState() => _WaChatSheetState();
}

class _WaChatSheetState extends State<_WaChatSheet> {
  Map<String, dynamic>? _d;
  String? _error;
  bool _sending = false;
  final _text = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await Api.raw.get('/leads/${widget.leadId}/wa-chat', queryParameters: {'limit': 100});
      if (mounted) setState(() { _d = (r.data as Map).cast<String, dynamic>(); _error = null; });
    } catch (e) {
      if (mounted) setState(() => _error = apiErrorMessage(e));
    }
  }

  Future<void> _send() async {
    final t = _text.text.trim();
    final d = _d;
    if (t.isEmpty || d == null || _sending) return;
    setState(() => _sending = true);
    final ok = await runAction(context, () => Api.post('/leads/${widget.leadId}/wa-chat/send', data: {'text': t, 'chat_id': d['chat_id'], 'session_id': (d['session'] as Map?)?['id']}));
    if (!mounted) return;
    setState(() => _sending = false);
    if (ok) { _text.clear(); _load(); }
  }

  /// The words, or what kind of message it was — never "[unknown]".
  String _body(Map m) {
    final c = m['content'];
    final t = c is Map ? (c['body'] ?? c['text'] ?? c['caption']) : c;
    if (t != null && '$t'.isNotEmpty) return '$t';
    final label = messageTypeLabel('${m['type'] ?? 'text'}');
    return label.isEmpty ? '' : label;
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    final msgs = ((d?['messages'] as List?) ?? const []).whereType<Map>().toList();
    final available = d?['available'] == true;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.85,
        child: Column(children: [
          ListTile(
            title: Text(widget.title, style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text(str((d?['session'] as Map?)?['name'], 'WhatsApp Chat')),
            trailing: IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(context)),
          ),
          const Divider(height: 1),
          Expanded(
            child: _error != null
                ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [Text(_error!, textAlign: TextAlign.center), const SizedBox(height: 10), OutlinedButton.icon(onPressed: () { setState(() => _error = null); _load(); }, icon: const Icon(Icons.refresh_rounded, size: 18), label: const Text('Try again'))])))
                : d == null
                    ? const Center(child: CircularProgressIndicator())
                    : !available
                        ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('No WhatsApp Chat conversation for this customer yet.', style: TextStyle(color: context.mutedColor))))
                        : ListView(
                            padding: const EdgeInsets.all(12),
                            children: [
                              for (final m in msgs)
                                Align(
                                  alignment: m['direction'] == 'outbound' ? Alignment.centerRight : Alignment.centerLeft,
                                  child: Container(
                                    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
                                    margin: const EdgeInsets.symmetric(vertical: 3),
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    decoration: BoxDecoration(color: m['direction'] == 'outbound' ? const Color(0xFFD9FDD3) : Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: context.lineColor)),
                                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(_body(m)), Text(when(m['created_at']), style: TextStyle(fontSize: 10, color: context.mutedColor))]),
                                  ),
                                ),
                            ],
                          ),
          ),
          if (available)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 8, 8),
                child: Row(children: [
                  Expanded(child: TextField(controller: _text, minLines: 1, maxLines: 4, decoration: const InputDecoration(isDense: true, hintText: 'Type a message…'))),
                  IconButton(onPressed: _sending ? null : _send, icon: _sending ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send_rounded)),
                ]),
              ),
            ),
        ]),
      ),
    );
  }
}

/// Pipeline: the stages as steps; tap one to move the lead there.
class LeadPipelineCard extends StatelessWidget {
  const LeadPipelineCard({super.key, required this.stage, required this.onStage});
  final String stage;
  final ValueChanged<String> onStage;
  static const _forward = ['new', 'contacted', 'follow_up', 'enrolled'];

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final idx = _forward.indexOf(stage);
    return _card(context, title: 'Pipeline', children: [
      if (stage == 'lost')
        Row(children: [
          const Chip(label: Text('Lost'), backgroundColor: Color(0xFFFEE2E2)),
          const SizedBox(width: 10),
          TextButton(onPressed: () => onStage('new'), child: const Text('Reopen as New')),
        ])
      else ...[
        Row(children: [
          for (var i = 0; i < _forward.length; i++) ...[
            Expanded(
              child: InkWell(
                onTap: () => onStage(_forward[i]),
                child: Column(children: [
                  CircleAvatar(
                    radius: 15,
                    backgroundColor: i == idx ? primary : (i < idx ? primary.withValues(alpha: 0.15) : context.altSurface),
                    child: Text(i < idx ? '✓' : '${i + 1}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: i == idx ? Colors.white : context.mutedColor)),
                  ),
                  const SizedBox(height: 4),
                  Text(stageLabel(_forward[i]), style: TextStyle(fontSize: 11, fontWeight: i == idx ? FontWeight.w700 : FontWeight.w400, color: i == idx ? null : context.mutedColor)),
                ]),
              ),
            ),
          ],
        ]),
        Align(alignment: Alignment.centerRight, child: TextButton(onPressed: () => onStage('lost'), child: const Text('Mark as Lost', style: TextStyle(color: Color(0xFFDC2626))))),
      ],
    ]);
  }
}

/// Lead information: the facts about the lead, read-only (Edit opens the form).
class LeadInfoTab extends StatelessWidget {
  const LeadInfoTab({super.key, required this.lead, required this.onEdit});
  final Rec lead;
  final VoidCallback onEdit;
  @override
  Widget build(BuildContext context) {
    final cats = (lead['categories'] as List?)?.map((e) => '$e').toList() ?? [if (str(lead['category']).isNotEmpty) str(lead['category'])];
    final staff = lead['assigned_to'] is Map ? str((lead['assigned_to'] as Map)['name']) : str((lead['staff'] as Map?)?['name']);
    final listing = lead['listing'] is Map ? str((lead['listing'] as Map)['title']) : '';
    return ListView(padding: const EdgeInsets.all(16), children: [
      _card(context, title: 'Lead information', trailing: TextButton(onPressed: onEdit, child: const Text('Edit')), children: [
        _kv(context, 'Source', str(lead['source_label'] ?? lead['source'])),
        _kv(context, 'Origin', str(lead['origin_label'])),
        _kv(context, 'Priority', str(lead['priority'], 'medium')),
        _kv(context, 'Categories', cats.join(', ')),
        _kv(context, 'Assigned to', staff.isEmpty ? 'Unassigned' : staff),
        _kv(context, 'Created', when(lead['created_at'])),
        _kv(context, 'Product / service', listing),
        _kv(context, 'Deal value', lead['sale_value'] == null ? '' : '₹${lead['sale_value']}'),
        if (str(lead['notes']).isNotEmpty) _kv(context, 'Notes', str(lead['notes'])),
      ]),
    ]);
  }
}

/// Chat: the WA Chat thread and the WA Cloud shared-inbox chats of this customer.
class LeadChatTab extends StatelessWidget {
  const LeadChatTab({super.key, required this.leadId, required this.lead});
  final int leadId;
  final Rec lead;
  @override
  Widget build(BuildContext context) {
    final c = lead['contact'] is Map ? (lead['contact'] as Map).cast<String, dynamic>() : <String, dynamic>{};
    final hidden = c['phone_is_real'] == false;
    return ListView(padding: const EdgeInsets.all(16), children: [
      _card(context, title: '💬 WA Chat', children: [
        Text('Chat with ${str(c['name'], 'this customer')} on the WhatsApp Chat session. Messages are sent through the chat gateway.', style: TextStyle(color: context.mutedColor, fontSize: 12.5)),
        const SizedBox(height: 10),
        FilledButton.icon(onPressed: () => showLeadWaChat(context, leadId, str(c['name'], str(c['phone']))), icon: const Icon(Icons.chat_rounded, size: 18), label: const Text('Open WA Chat')),
      ]),
      _card(context, title: '📥 WA shared inbox', children: [
        Text(hidden ? "Needs the customer's real number — WhatsApp is hiding it." : 'The shared WA Cloud inbox. Free text inside 24 hours of their last message; an approved template after that.', style: TextStyle(color: context.mutedColor, fontSize: 12.5)),
        const SizedBox(height: 10),
        OutlinedButton.icon(onPressed: hidden ? null : () => openLeadInbox(context, c), icon: const Icon(Icons.inbox_rounded, size: 18), label: const Text('Open shared inbox')),
      ]),
    ]);
  }
}

/// Who referred this lead — shown, added, changed or removed. Adding offers an existing contact (search) or a brand-new one (name + number).
class LeadReferredTab extends StatelessWidget {
  const LeadReferredTab({super.key, required this.leadId, required this.lead, required this.onChanged});
  final int leadId;
  final Rec lead;
  final VoidCallback onChanged;

  Future<void> _remove(BuildContext context) async {
    final ok = await runAction(context, () => Api.put('/leads/$leadId/referrer', data: {'contact_id': null}), success: 'Referrer removed.');
    if (ok) onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final r = lead['referred_by'] is Map ? (lead['referred_by'] as Map).cast<String, dynamic>() : null;
    return ListView(padding: const EdgeInsets.all(16), children: [
      _card(
        context,
        title: '🤝 Referred by',
        trailing: TextButton(
          onPressed: () async {
            final saved = await _showReferrerSheet(context, leadId);
            if (saved) onChanged();
          },
          child: Text(r == null ? '+ Add referrer' : 'Change'),
        ),
        children: [
          if (r == null)
            Text('Nobody recorded. Add the customer or partner who sent this lead.', style: TextStyle(color: context.mutedColor))
          else ...[
            _kv(context, 'Name', str(r['name'])),
            _kv(context, 'Phone', str(r['phone'])),
            Align(alignment: Alignment.centerLeft, child: TextButton(onPressed: () => _remove(context), child: const Text('Remove referrer', style: TextStyle(color: Color(0xFFDC2626))))),
          ],
        ],
      ),
    ]);
  }
}

/// "Who referred this lead?" — Existing contact (search a name or number) or New contact (name + number; an existing number is reused). Returns true once saved.
Future<bool> _showReferrerSheet(BuildContext context, int leadId) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    builder: (_) => _ReferrerSheet(leadId: leadId),
  );
  return saved == true;
}

class _ReferrerSheet extends StatefulWidget {
  const _ReferrerSheet({required this.leadId});
  final int leadId;
  @override
  State<_ReferrerSheet> createState() => _ReferrerSheetState();
}

class _ReferrerSheetState extends State<_ReferrerSheet> {
  bool _isNew = false;
  final _search = TextEditingController();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  List<Map<String, dynamic>> _found = [];
  bool _searching = false, _saving = false;
  String? _error;
  int _seq = 0;

  @override
  void dispose() {
    _search.dispose();
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _lookup(String q) async {
    final t = q.trim();
    final mine = ++_seq;
    if (t.length < 2) { setState(() { _found = []; _searching = false; }); return; }
    setState(() => _searching = true);
    try {
      final rows = await Api.list('/contacts', query: {'search': t, 'per_page': 8});
      if (mounted && mine == _seq) setState(() { _found = rows; _searching = false; });
    } catch (_) {
      if (mounted && mine == _seq) setState(() => _searching = false);
    }
  }

  Future<void> _save(Map<String, dynamic> body) async {
    setState(() { _saving = true; _error = null; });
    try {
      await Api.put('/leads/${widget.leadId}/referrer', data: body);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() { _saving = false; _error = apiErrorMessage(e); });
    }
  }

  @override
  Widget build(BuildContext context) {
    final digits = _phone.text.replaceAll(RegExp(r'\D'), '');
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Who referred this lead?', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            OutlinePills(labels: const ['Existing contact', 'New contact'], index: _isNew ? 1 : 0, onChanged: (i) => setState(() { _isNew = i == 1; _error = null; })),
            const SizedBox(height: 14),
            if (!_isNew) ...[
              TextField(
                controller: _search,
                autofocus: true,
                onChanged: _lookup,
                decoration: const InputDecoration(hintText: 'Search name or number…', prefixIcon: Icon(Icons.search_rounded), border: OutlineInputBorder(), isDense: true),
              ),
              if (_searching) const Padding(padding: EdgeInsets.all(12), child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))),
              for (final c in _found)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const CircleAvatar(radius: 16, child: Icon(Icons.person_outline_rounded, size: 18)),
                  title: Text(str(c['name'], 'Unnamed contact')),
                  subtitle: Text(str(c['phone'])),
                  onTap: _saving ? null : () => _save({'contact_id': c['id']}),
                ),
              if (!_searching && _search.text.trim().length >= 2 && _found.isEmpty)
                Padding(padding: const EdgeInsets.only(top: 10), child: Text('No contact found — use "New contact" to add them.', style: TextStyle(color: context.mutedColor, fontSize: 12.5))),
            ] else ...[
              TextField(controller: _name, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder(), isDense: true)),
              const SizedBox(height: 10),
              TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: 'Phone * (with country code)', hintText: '919876543210', border: OutlineInputBorder(), isDense: true),
              ),
              const SizedBox(height: 6),
              Text('If a contact with this number exists, it is reused — no duplicate is made.', style: TextStyle(color: context.mutedColor, fontSize: 11.5)),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _saving || digits.length < 7 ? null : () => _save({'name': _name.text.trim(), 'phone': _phone.text.trim()}),
                  child: Text(_saving ? 'Saving…' : 'Save referrer'),
                ),
              ),
            ],
            if (_error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_error!, style: const TextStyle(color: Color(0xFFDC2626), fontSize: 12.5))),
          ]),
        ),
      ),
    );
  }
}

class LeadStaffTab extends StatelessWidget {
  const LeadStaffTab({super.key, required this.lead, required this.onAssign, required this.onClaim});
  final Rec lead;
  final VoidCallback onAssign, onClaim;
  @override
  Widget build(BuildContext context) {
    final a = lead['assigned_to'] is Map ? (lead['assigned_to'] as Map).cast<String, dynamic>() : null;
    return ListView(padding: const EdgeInsets.all(16), children: [
      _card(context, title: '🧑‍💼 Assigned staff', children: [
        if (a != null) ListTile(contentPadding: EdgeInsets.zero, leading: CircleAvatar(child: Text(str(a['name']).isEmpty ? '?' : str(a['name'])[0].toUpperCase())), title: Text(str(a['name']), style: const TextStyle(fontWeight: FontWeight.w700)), subtitle: lead['assigned_at'] != null ? Text('since ${when(lead['assigned_at'])}') : null)
        else Text('Not assigned to anyone yet', style: TextStyle(color: context.mutedColor)),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: OutlinedButton.icon(onPressed: onAssign, icon: const Icon(Icons.person_add_alt_rounded, size: 18), label: Text(a == null ? 'Assign staff' : 'Switch staff'))),
          if (a == null) ...[const SizedBox(width: 8), Expanded(child: FilledButton(onPressed: onClaim, child: const Text('Assign to me')))],
        ]),
      ]),
    ]);
  }
}

/// Categories (pick several; the first is the primary) and the contact's labels.
class LeadCategoryTab extends StatefulWidget {
  const LeadCategoryTab({super.key, required this.leadId, required this.lead, required this.onChanged});
  final int leadId;
  final Rec lead;
  final VoidCallback onChanged;
  @override
  State<LeadCategoryTab> createState() => _LeadCategoryTabState();
}

class _LeadCategoryTabState extends State<LeadCategoryTab> {
  List<String> _all = [];
  late List<String> _mine = (widget.lead['categories'] as List?)?.map((e) => '$e').toList() ?? [if (str(widget.lead['category']).isNotEmpty) str(widget.lead['category'])];
  bool _busy = false;
  List<Map<String, dynamic>> _allLabels = [];
  late List<int> _selLabels = [for (final l in (((widget.lead['contact'] as Map?)?['labels'] as List?) ?? const []).whereType<Map>()) (l['id'] as num).toInt()];

  @override
  void initState() {
    super.initState();
    Api.one('/lead-categories', query: {'names_only': true}).then((r) {
      if (mounted) setState(() => _all = [for (final n in (r['categories'] as List? ?? const [])) '$n']);
    }).catchError((_) {});
    Api.list('/labels').then((r) { if (mounted) setState(() => _allLabels = r); }).catchError((_) {});
  }

  int? get _contactId => ((widget.lead['contact'] as Map?)?['id'] as num?)?.toInt();

  Future<void> _syncLabels(List<int> next) async {
    final cid = _contactId;
    if (cid == null) return;
    final prev = _selLabels;
    setState(() { _selLabels = next; _busy = true; });
    try {
      await Api.post('/contacts/$cid/labels', data: {'label_ids': next});
      widget.onChanged();
    } catch (e) {
      if (mounted) {
        setState(() => _selLabels = prev);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// New label (name + colour), created and added to this contact in one go.
  Future<void> _newLabel() async {
    final made = await showDialog<Map<String, String>>(context: context, builder: (_) => const _NewLabelDialog());
    if (made == null || !mounted) return;
    try {
      final r = await Api.post('/labels', data: made);
      var created = (r['label'] ?? r['data'] ?? r);
      int? newId = created is Map ? (created['id'] as num?)?.toInt() : null;
      final fresh = await Api.list('/labels');
      newId ??= (fresh.firstWhere((l) => l['name'] == made['name'], orElse: () => <String, dynamic>{})['id'] as num?)?.toInt();
      if (!mounted) return;
      setState(() => _allLabels = fresh);
      if (newId != null) await _syncLabels([..._selLabels, newId]);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
    }
  }

  Future<void> _toggle(String n) async {
    final next = _mine.contains(n) ? _mine.where((x) => x != n).toList() : [..._mine, n];
    setState(() { _mine = next; _busy = true; });
    try {
      await Api.put('/leads/${widget.leadId}/categories', data: {'categories': next});
      widget.onChanged();
    } catch (e) {
      if (mounted) {
        setState(() => _mine = _mine.contains(n) ? _mine.where((x) => x != n).toList() : [..._mine, n]);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return ListView(padding: const EdgeInsets.all(16), children: [
      _card(context, title: '🏷️ Lead category', children: [
        Text('Choose as many as fit. Tap one again to take it off. The first is the primary category.', style: TextStyle(color: context.mutedColor, fontSize: 12)),
        const SizedBox(height: 10),
        if (_all.isEmpty) Text('No categories yet.', style: TextStyle(color: context.mutedColor)),
        Wrap(spacing: 8, runSpacing: 4, children: [
          for (final n in _all)
            ChoiceChip(
              avatar: Icon(_mine.contains(n) ? Icons.check_circle : Icons.circle_outlined, size: 16, color: _mine.contains(n) ? primary : null),
              label: Text(n, style: TextStyle(fontSize: 12.5, fontWeight: _mine.contains(n) ? FontWeight.w700 : FontWeight.w500)),
              selected: _mine.contains(n),
              showCheckmark: false,
              backgroundColor: Colors.transparent,
              selectedColor: Colors.transparent,
              side: BorderSide(color: _mine.contains(n) ? primary : context.lineColor, width: _mine.contains(n) ? 1.6 : 1),
              onSelected: _busy ? null : (_) => _toggle(n),
            ),
        ]),
      ]),
      _card(context, title: 'Contact labels', trailing: TextButton(onPressed: _contactId == null ? null : _newLabel, child: const Text('+ New label')), children: [
        Text('Selected (${_selLabels.length})', style: TextStyle(fontSize: 11.5, color: context.mutedColor, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        if (_selLabels.isEmpty) Text('None selected.', style: TextStyle(color: context.mutedColor, fontSize: 12.5)),
        Wrap(spacing: 6, runSpacing: 4, children: [
          for (final l in _allLabels.where((l) => _selLabels.contains((l['id'] as num).toInt())))
            InputChip(
              label: Text(str(l['name']), style: const TextStyle(fontSize: 12, color: Colors.white)),
              backgroundColor: _labelColor(l),
              deleteIconColor: Colors.white,
              onDeleted: _busy ? null : () => _syncLabels(_selLabels.where((x) => x != (l['id'] as num).toInt()).toList()),
              visualDensity: VisualDensity.compact,
            ),
        ]),
        const SizedBox(height: 12),
        Text('Available', style: TextStyle(fontSize: 11.5, color: context.mutedColor, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 4, children: [
          for (final l in _allLabels.where((l) => !_selLabels.contains((l['id'] as num).toInt())))
            ActionChip(
              label: Text('+ ${str(l['name'])}', style: TextStyle(fontSize: 12, color: _labelColor(l))),
              backgroundColor: Colors.transparent,
              side: BorderSide(color: _labelColor(l)),
              onPressed: _busy ? null : () => _syncLabels([..._selLabels, (l['id'] as num).toInt()]),
              visualDensity: VisualDensity.compact,
            ),
          if (_allLabels.isEmpty) Text('No labels yet.', style: TextStyle(color: context.mutedColor, fontSize: 12.5)),
        ]),
      ]),
    ]);
  }

  Color _labelColor(Map l) {
    final h = '${l['color'] ?? ''}'.replaceAll('#', '');
    final v = h.length == 6 ? int.tryParse('FF$h', radix: 16) : null;
    return v == null ? const Color(0xFF6B7280) : Color(v);
  }
}

/// New label: a name and a colour, with a live preview.
class _NewLabelDialog extends StatefulWidget {
  const _NewLabelDialog();
  @override
  State<_NewLabelDialog> createState() => _NewLabelDialogState();
}

class _NewLabelDialogState extends State<_NewLabelDialog> {
  static const _palette = ['#2563eb', '#16a34a', '#f59e0b', '#dc2626', '#9333ea', '#0891b2', '#db2777', '#64748b'];
  final _name = TextEditingController();
  String _color = _palette[1];

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Color _c(String h) => Color(int.parse('FF${h.substring(1)}', radix: 16));

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New label'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('It will be added to this contact', style: TextStyle(color: context.mutedColor, fontSize: 12)),
        const SizedBox(height: 10),
        TextField(controller: _name, autofocus: true, maxLength: 40, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder(), isDense: true)),
        const SizedBox(height: 4),
        const Text('Colour', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        const SizedBox(height: 8),
        Wrap(spacing: 10, runSpacing: 8, children: [
          for (final h in _palette)
            GestureDetector(
              onTap: () => setState(() => _color = h),
              child: CircleAvatar(radius: 14, backgroundColor: _c(h), child: _color == h ? const Icon(Icons.check, size: 16, color: Colors.white) : null),
            ),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          const Text('Preview: ', style: TextStyle(fontSize: 12.5)),
          Chip(label: Text(_name.text.trim().isEmpty ? 'Label' : _name.text.trim(), style: const TextStyle(fontSize: 12, color: Colors.white)), backgroundColor: _c(_color), visualDensity: VisualDensity.compact),
        ]),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _name.text.trim().isEmpty ? null : () => Navigator.pop(context, {'name': _name.text.trim(), 'color': _color}), child: const Text('Add label')),
      ],
    );
  }
}

/// Campaigns: how many WA Cloud campaigns were sent to this number and how many got a reply.
class LeadCampaignsTab extends StatefulWidget {
  const LeadCampaignsTab({super.key, required this.leadId});
  final int leadId;
  @override
  State<LeadCampaignsTab> createState() => _LeadCampaignsTabState();
}

class _LeadCampaignsTabState extends State<LeadCampaignsTab> {
  Map<String, dynamic>? _d;
  String? _error;

  @override
  void initState() {
    super.initState();
    Api.raw.get('/leads/${widget.leadId}/campaigns').then((r) {
      if (mounted) setState(() => _d = (r.data as Map).cast<String, dynamic>());
    }).catchError((e) {
      if (mounted) setState(() => _error = apiErrorMessage(e));
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return Center(child: Text(_error!));
    final d = _d;
    if (d == null) return const Center(child: CircularProgressIndicator());
    final s = (d['summary'] as Map?)?.cast<String, dynamic>() ?? {};
    final items = ((d['items'] as List?) ?? const []).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
    final stats = [
      ('Campaigns sent', '${s['campaigns_sent'] ?? 0}'), ('Messages sent', '${s['messages_sent'] ?? 0}'), ('Delivered', '${s['delivered'] ?? 0}'),
      ('Read', '${s['read'] ?? 0}'), ('Responded', '${s['responded'] ?? 0}'), ('Response rate', '${s['response_rate'] ?? 0}%'),
    ];
    return ListView(padding: const EdgeInsets.all(16), children: [
      GridView.count(
        crossAxisCount: 3, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: 1.5,
        children: [
          for (final (l, v) in stats)
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(border: Border.all(color: context.lineColor), borderRadius: BorderRadius.circular(12)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [Text(l, style: TextStyle(fontSize: 11, color: context.mutedColor)), Text(v, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800))]),
            ),
        ],
      ),
      const SizedBox(height: 14),
      _card(context, title: 'Campaign history', children: [
        if (items.isEmpty) Text('No campaign has been sent to this contact yet.', style: TextStyle(color: context.mutedColor)),
        for (final i in items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(str(i['name']), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                Text('${i['sent_at'] != null ? when(i['sent_at']) : 'not sent'} · ${str(i['status'])}${i['read_at'] != null ? ' · read' : ''}', style: TextStyle(fontSize: 11.5, color: context.mutedColor)),
              ])),
              if (i['responded'] == true) Text('✓ ${i['replies']} repl${i['replies'] == 1 ? 'y' : 'ies'}', style: const TextStyle(color: Color(0xFF16A34A), fontSize: 12, fontWeight: FontWeight.w600)),
            ]),
          ),
        if (d['note'] != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text('${d['note']}', style: TextStyle(fontSize: 11, color: context.mutedColor))),
      ]),
    ]);
  }
}
