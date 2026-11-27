import 'dart:async';

import 'package:flutter/material.dart';
import 'package:unichat_mobile_app/core/constants/app_colors.dart';
import 'package:unichat_mobile_app/features/modules/_shared.dart';

/// What the "New lead" form knows about the customer: what was typed, and the existing contact the number matched (if any).
class LeadContactState {
  final phone = TextEditingController();
  final name = TextEditingController();
  final email = TextEditingController();
  Map<String, dynamic>? existing;
  bool checked = false;

  bool get ready => checked && phone.text.replaceAll(RegExp(r'\D'), '').length >= 7;

  /// Saves the contact (creating it, or updating an edited name / email) and returns its id.
  Future<int> save() async {
    final nm = name.text.trim(), em = email.text.trim();
    final hit = existing;
    if (hit != null) {
      if (nm != '${hit['name'] ?? ''}' || em != '${hit['email'] ?? ''}') {
        await Api.put('/contacts/${hit['id']}', data: {if (nm.isNotEmpty) 'name': nm, if (em.isNotEmpty) 'email': em});
      }
      return (hit['id'] as num).toInt();
    }
    final r = await Api.post('/contacts', data: {'phone': phone.text.trim(), if (nm.isNotEmpty) 'name': nm, if (em.isNotEmpty) 'email': em});
    final c = r['contact'] is Map ? r['contact'] as Map : r;
    return (c['id'] as num).toInt();
  }

  void dispose() { phone.dispose(); name.dispose(); email.dispose(); }
}

/// Phone-first customer fields, like the web "Add lead": type the number and we check whether that customer is already a contact,
/// filling in their name and email. A number nobody has is added as a new contact.
class LeadContactFields extends StatefulWidget {
  const LeadContactFields({super.key, required this.state});
  final LeadContactState state;
  @override
  State<LeadContactFields> createState() => _LeadContactFieldsState();
}

enum _Check { idle, checking, pick, none, existing, fresh }

/// Same number whether or not one side carries the country code / a leading 0 (9876543210 = 919876543210 = 09876543210).
bool _sameNumber(String stored, String typed) {
  if (stored.isEmpty || typed.isEmpty) return false;
  if (stored == typed) return true;
  final short = stored.length < typed.length ? stored : typed, long = stored.length < typed.length ? typed : stored;
  return short.length >= 8 && long.endsWith(short);
}

class _LeadContactFieldsState extends State<LeadContactFields> {
  Timer? _debounce;
  int _seq = 0;   // a slow answer for an older number must not overwrite the newer one
  _Check _check = _Check.idle;
  List<Map<String, dynamic>> _matches = const [];   // customers whose number matches what is typed so far (any country-code form)

  LeadContactState get _s => widget.state;

  /// Choose an existing customer: fill the name / email and use their stored number.
  void _pick(Map<String, dynamic> hit) {
    _s.existing = hit;
    _s.checked = true;
    _s.phone.text = '${hit['phone'] ?? _s.phone.text}';
    _s.name.text = '${hit['name'] ?? ''}';
    _s.email.text = '${hit['email'] ?? ''}';
    _matches = const [];
    _check = _Check.existing;
  }

  void _onPhone(String v) {
    _debounce?.cancel();
    final digits = v.replaceAll(RegExp(r'\D'), '');
    _s.existing = null;
    _s.checked = false;
    if (digits.length < 5) { setState(() { _check = _Check.idle; _matches = const []; }); return; }   // search starts from the 5th digit — the full number isn't needed
    setState(() => _check = _Check.checking);
    final mine = ++_seq;
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      try {
        final rows = await Api.list('/contacts', query: {'search': digits, 'per_page': 8});
        if (!mounted || mine != _seq) return;
        String digitsOf(Map c) => '${c['phone'] ?? ''}'.replaceAll(RegExp(r'\D'), '');
        final all = rows.cast<Map<String, dynamic>>();
        final exact = all.where((c) => _sameNumber(digitsOf(c), digits)).toList();
        final partial = all.where((c) => digitsOf(c).contains(digits)).toList();   // still typing: the start / middle of a stored number
        setState(() {
          if (exact.length == 1) {
            _pick(exact.first);                                   // the number is complete and belongs to exactly one customer
          } else if (exact.length > 1 || partial.isNotEmpty) {
            _s.existing = null; _s.checked = false;
            _matches = (exact.isNotEmpty ? exact : partial).take(5).toList();
            _check = _Check.pick;                                 // several (or still-partial) matches: show their names to choose from
          } else {
            _matches = const [];
            if (digits.length >= 7) { _s.checked = true; _check = _Check.fresh; }   // a complete-looking number nobody has: add as new
            else { _check = _Check.none; }                                          // still short: no match yet, keep typing
          }
        });
      } catch (_) {
        if (!mounted || mine != _seq) return;
        setState(() { _s.checked = true; _check = _Check.fresh; });   // couldn't check — treat as new; the server still refuses a duplicate
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final (msg, color) = switch (_check) {
      _Check.idle => ('Type at least 5 digits of the number — we look for this customer in your contacts.', AppColors.textLight),
      _Check.checking => ('Checking contacts…', AppColors.textLight),
      _Check.none => ('No customer matches these digits yet — keep typing.', AppColors.textLight),
      _Check.pick => ('${_matches.length} customer${_matches.length == 1 ? '' : 's'} found — tap one, or keep typing the full number.', AppColors.textLight),
      _Check.existing => ('✓ Existing contact found — details filled in. You can edit them.', const Color(0xFF16A34A)),
      _Check.fresh => ('New number — a new contact will be added with the details below.', const Color(0xFFD97706)),
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      TextFormField(
        controller: _s.phone,
        keyboardType: TextInputType.phone,
        autofocus: true,
        onChanged: _onPhone,
        validator: (v) => (v ?? '').replaceAll(RegExp(r'\D'), '').length < 7 ? 'Enter the customer\'s phone number' : null,
        decoration: const InputDecoration(labelText: 'Customer phone number *', hintText: 'e.g. 9876543210 or +91 98765 43210', border: OutlineInputBorder()),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(2, 6, 2, 8),
        child: Text(msg, style: TextStyle(fontSize: 12, color: color)),
      ),
      for (final c in (_check == _Check.pick ? _matches : const <Map<String, dynamic>>[]))
        Card(
          margin: const EdgeInsets.only(bottom: 6),
          child: ListTile(
            dense: true,
            leading: const Icon(Icons.person_outline_rounded),
            title: Text('${c['name'] ?? ''}'.trim().isEmpty ? 'Unnamed customer' : '${c['name']}'),
            subtitle: Text('${c['phone'] ?? ''}'),
            onTap: () => setState(() => _pick(c)),
          ),
        ),
      if (_check == _Check.existing || _check == _Check.fresh) ...[
        TextFormField(controller: _s.name, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Customer name', border: OutlineInputBorder())),
        const SizedBox(height: 10),
        TextFormField(controller: _s.email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email (optional)', border: OutlineInputBorder())),
        const SizedBox(height: 4),
      ],
    ]);
  }
}
