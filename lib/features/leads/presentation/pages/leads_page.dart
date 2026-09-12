import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:unichat_mobile_app/core/constants/app_colors.dart';
import 'package:unichat_mobile_app/core/network/dio_client.dart';
import 'package:unichat_mobile_app/core/utils/format_utils.dart';
import 'package:unichat_mobile_app/core/widgets/app_avatar.dart';
import 'package:unichat_mobile_app/core/widgets/app_empty_state.dart';
import 'package:unichat_mobile_app/core/widgets/lead_score_badge.dart';
import 'package:unichat_mobile_app/features/modules/_shared.dart';

class LeadsPage extends StatefulWidget {
  const LeadsPage({super.key});
  @override
  State<LeadsPage> createState() => _LeadsPageState();
}

class _LeadsPageState extends State<LeadsPage> {
  List<dynamic> _leads   = [];
  bool _loading          = true;
  String _statusFilter   = 'all';
  int _page              = 1;
  bool _hasMore          = true;

  final _filters = ['all', 'pending', 'assigned', 'accepted', 'ai_handling', 'completed'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool reset = false}) async {
    if (reset) { _page = 1; _leads = []; }
    setState(() => _loading = true);
    try {
      final params = {'page': _page, if (_statusFilter != 'all') 'status': _statusFilter};
      final res = await DioClient.laravelDio.get('/leads', queryParameters: params);
      final data = res.data as Map<String, dynamic>;
      final items = (data['data'] as List?) ?? [];
      setState(() {
        _leads  = reset ? items : [..._leads, ...items];
        _hasMore = items.isNotEmpty;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _createLead() async {
    List<Map<String, dynamic>> contacts;
    try {
      contacts = await Api.list('/contacts', query: {'per_page': 100});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
      }
      return;
    }
    if (!mounted || contacts.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Add a contact first.')));
      }
      return;
    }
    List<Map<String, dynamic>> staff;
    try {
      staff = await Api.list('/staff');
    } catch (_) {
      staff = const [];
    }
    if (!mounted) return;
    final data = <String, dynamic>{};
    final ok = await showFormSheet(
      context,
      title: 'New lead',
      submitLabel: 'Create',
      fields: (ctx) => [
        FSelect<Map<String, dynamic>>(
          label: 'Contact',
          options: contacts,
          labelOf: (c) => '${c['name'] ?? c['phone']} · ${c['phone'] ?? ''}',
          onSaved: (c) => data['contact_id'] = c?['id'],
        ),
        FSelect<String>(
          label: 'Priority',
          options: const ['low', 'medium', 'high'],
          initial: 'medium',
          onSaved: (v) => data['priority'] = v ?? 'medium',
        ),
        FText(
          label: 'Category',
          onSaved: (v) => v.isEmpty ? null : data['category'] = v,
        ),
        if (staff.isNotEmpty)
          FSelect<Map<String, dynamic>>(
            label: 'Assign to (optional)',
            options: staff,
            labelOf: (s) => '${s['name']}',
            onSaved: (s) => s?['id'] != null ? data['assigned_to'] = s!['id'] : null,
          ),
        FText(
          label: 'Notes',
          maxLines: 3,
          onSaved: (v) => v.isEmpty ? null : data['notes'] = v,
        ),
      ],
      onSubmit: () => Api.post('/leads', data: data),
    );
    if (ok) _load(reset: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createLead,
        icon: const Icon(Icons.add_rounded),
        label: const Text('New lead'),
      ),
      appBar: AppBar(
        title: const Text('Leads'),
        actions: [
          IconButton(icon: const Icon(Icons.add_circle_outline), onPressed: _createLead),
          IconButton(icon: const Icon(Icons.notifications_outlined), onPressed: () => context.push('/notifications')),
        ],
      ),
      body: Column(
        children: [
          _filterChips(),
          Expanded(
            child: _loading && _leads.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : _leads.isEmpty
                    ? AppEmptyState(
                        icon: Icons.people_outline,
                        title: 'No leads',
                        subtitle: 'No leads found for this filter.',
                      )
                    : RefreshIndicator(
                        onRefresh: () => _load(reset: true),
                        child: ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: _leads.length + (_hasMore ? 1 : 0),
                          itemBuilder: (_, i) {
                            if (i == _leads.length) {
                              return Center(
                                child: TextButton(
                                  onPressed: () { _page++; _load(); },
                                  child: const Text('Load more'),
                                ),
                              );
                            }
                            return _leadCard(_leads[i]);
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _filterChips() {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        scrollDirection: Axis.horizontal,
        itemCount: _filters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final f = _filters[i];
          final sel = _statusFilter == f;
          return ChoiceChip(
            label: Text(f.toUpperCase()),
            selected: sel,
            onSelected: (_) { setState(() => _statusFilter = f); _load(reset: true); },
            selectedColor: AppColors.primary,
            labelStyle: TextStyle(color: sel ? Colors.white : AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w700),
          );
        },
      ),
    );
  }

  Widget _leadCard(Map<String, dynamic> lead) {
    final contact = lead['contact'] as Map<String, dynamic>?;
    final staff   = lead['staff']   as Map<String, dynamic>?;
    final name    = contact?['name'] as String? ?? 'Unknown';
    final phone   = contact?['phone'] as String? ?? '';
    final score   = lead['lead_score'] as int? ?? 0;
    final status  = lead['status'] as String? ?? '';
    final sla     = lead['sla_breached'] as bool? ?? false;
    final ts      = lead['created_at'] != null ? DateTime.tryParse(lead['created_at'] as String) : null;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: () => context.push('/leads/${lead['id']}'),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  AppAvatar(name: name, size: 40),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                        Text(FormatUtils.phone(phone), style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                      ],
                    ),
                  ),
                  LeadScoreBadge(score: score),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  StageBadge(stage: status),
                  if (sla) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: AppColors.error.withAlpha(20), borderRadius: BorderRadius.circular(8)),
                      child: const Text('⏰ SLA', style: TextStyle(color: AppColors.error, fontSize: 10, fontWeight: FontWeight.w700)),
                    ),
                  ],
                  const Spacer(),
                  if (staff != null)
                    Text('👤 ${staff['name']}', style: const TextStyle(fontSize: 11, color: AppColors.textLight)),
                  const SizedBox(width: 6),
                  Text(FormatUtils.relative(ts), style: const TextStyle(fontSize: 11, color: AppColors.textLight)),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _actionBtn('💬 Chat', AppColors.primary, () {}),
                  const SizedBox(width: 8),
                  _actionBtn('Details →', AppColors.textSecondary, () => context.push('/leads/${lead['id']}')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actionBtn(String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: color.withAlpha(20),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withAlpha(60)),
        ),
        child: Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
      ),
    );
  }
}
