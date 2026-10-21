// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:unichat_mobile_app/features/modules/_shared.dart';
import 'books_common.dart';

class BooksLedgersTab extends StatefulWidget {
  const BooksLedgersTab({super.key});
  @override
  State<BooksLedgersTab> createState() => _BooksLedgersTabState();
}

class _BooksLedgersTabState extends State<BooksLedgersTab> with AutomaticKeepAliveClientMixin {
  List<Rec> _rows = [];
  bool _loading = true;
  String? _error;
  String _nature = '';
  final _search = TextEditingController();

  @override
  bool get wantKeepAlive => true;

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
    setState(() { _loading = true; _error = null; });
    try {
      final d = await getJson('/accounts/ledgers', query: {if (_nature.isNotEmpty) 'nature': _nature, if (_search.text.isNotEmpty) 'search': _search.text});
      if (mounted) setState(() { _rows = asRecs(d['ledgers']); _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = apiErrorMessage(e); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _form(null), icon: const Icon(Icons.add_rounded), label: const Text('Ledger'),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: TextField(
            controller: _search,
            onSubmitted: (_) => _load(),
            decoration: const InputDecoration(isDense: true, hintText: 'Search ledger…', prefixIcon: Icon(Icons.search_rounded, size: 20)),
          ),
        ),
        SizedBox(
          height: 52,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), children: [
            for (final n in ['', 'asset', 'liability', 'income', 'expense', 'equity'])
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(n.isEmpty ? 'All' : n[0].toUpperCase() + n.substring(1)),
                  selected: _nature == n,
                  onSelected: (_) { setState(() => _nature = n); _load(); },
                ),
              ),
          ]),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(child: Text(_error!))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 90),
                        itemCount: _rows.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          final l = _rows[i];
                          final bal = numOf(l['balance']);
                          return RecordCard(
                            title: str(l['name']),
                            subtitle: '${ledgerGroups[l['group']]?.$2 ?? l['group']}${l['gstin'] != null ? ' · ${l['gstin']}' : ''}',
                            leadingIcon: Icons.menu_book_rounded,
                            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                              Text('${inr(bal.abs())}${bal == 0 ? '' : bal > 0 ? ' Dr' : ' Cr'}', style: const TextStyle(fontWeight: FontWeight.w600)),
                              RowMenu(items: [
                                ('Edit', Icons.edit_rounded, () => _form(l)),
                                if (l['system_key'] == null) ('Delete', Icons.delete_outline_rounded, () => _delete(l)),
                              ]),
                            ]),
                            onTap: () => _form(l),
                          );
                        },
                      ),
                    ),
        ),
      ]),
    );
  }

  Future<void> _delete(Rec l) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete ledger?'),
        content: Text('Delete "${l['name']}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (yes == true && await runAction(context, () => Api.delete('/accounts/ledgers/${l['id']}'), success: 'Deleted.')) _load();
  }

  Future<void> _form(Rec? l) async {
    var name = l == null ? '' : str(l['name'], '');
    var group = l == null ? 'indirect_expense' : str(l['group'], 'other');
    num? opening = l == null ? null : numOf(l['opening_balance']) == 0 ? null : numOf(l['opening_balance']);
    var openingType = l == null ? 'dr' : str(l['opening_type'], 'dr');
    var gstin = l == null ? '' : str(l['gstin'], '');
    String? state = l?['state_code'] as String?;
    var phone = l == null ? '' : str(l['phone'], '');
    var email = l == null ? '' : str(l['email'], '');
    var address = l == null ? '' : str(l['address'], '');
    var city = l == null ? '' : str(l['city'], '');
    var pincode = l == null ? '' : str(l['pincode'], '');
    final system = l?['system_key'] != null;

    final saved = await showFormSheet(
      context,
      title: l == null ? 'New ledger' : 'Edit ledger',
      fields: (ctx) => [
        FText(label: 'Name', initial: name, required: true, onSaved: (v) => name = v),
        StatefulBuilder(builder: (ctx, setS) {
          final party = group == 'debtor' || group == 'creditor';
          return Column(children: [
            FField(label: 'Ledger type', child: DropdownButtonFormField<String>(
              initialValue: group, isExpanded: true,
              items: [for (final e in ledgerGroups.entries) DropdownMenuItem(value: e.key, child: Text(e.value.$2))],
              onChanged: system ? null : (v) => setS(() => group = v ?? group),
            )),
            FNumber(label: 'Opening balance', initial: opening, onSaved: (v) => opening = v),
            FSelect<String>(label: 'Opening is', options: const ['dr', 'cr'], initial: openingType, labelOf: (v) => v == 'dr' ? 'Debit (Dr)' : 'Credit (Cr)', onSaved: (v) => openingType = v ?? 'dr'),
            if (party) ...[
              FText(label: 'GSTIN', initial: gstin == '—' ? '' : gstin, onSaved: (v) => gstin = v.toUpperCase()),
              FSelect<String>(label: 'State', options: gstStates.keys.toList(), initial: state, labelOf: (k) => '$k — ${gstStates[k]}', onSaved: (v) => state = v),
              FText(label: 'Phone', initial: phone == '—' ? '' : phone, keyboardType: TextInputType.phone, onSaved: (v) => phone = v),
              FText(label: 'Email', initial: email == '—' ? '' : email, onSaved: (v) => email = v),
              FText(label: 'Address', initial: address == '—' ? '' : address, maxLines: 2, onSaved: (v) => address = v),
              FText(label: 'City', initial: city == '—' ? '' : city, onSaved: (v) => city = v),
              FText(label: 'Pincode', initial: pincode == '—' ? '' : pincode, keyboardType: TextInputType.number, onSaved: (v) => pincode = v),
            ],
          ]);
        }),
      ],
      onSubmit: () async {
        final party = group == 'debtor' || group == 'creditor';
        final body = {
          'name': name, 'nature': ledgerGroups[group]!.$1, 'group': group,
          'opening_balance': opening ?? 0, 'opening_type': openingType,
          if (party) ...{
            'gstin': gstin.isEmpty ? null : gstin, 'state_code': state,
            'phone': phone.isEmpty ? null : phone, 'email': email.isEmpty ? null : email, 'address': address.isEmpty ? null : address,
            'city': city.isEmpty ? null : city, 'pincode': pincode.isEmpty ? null : pincode,
          },
        };
        l == null ? await Api.post('/accounts/ledgers', data: body) : await Api.put('/accounts/ledgers/${l['id']}', data: body);
      },
    );
    if (saved) _load();
  }
}
