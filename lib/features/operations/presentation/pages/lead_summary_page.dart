// ignore_for_file: use_build_context_synchronously
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:go_router/go_router.dart";
import "package:unichat_mobile_app/features/modules/module_providers.dart";
import "package:unichat_mobile_app/features/modules/_shared.dart";
import "package:unichat_mobile_app/features/leads/lead_stage.dart";

// ══════════════════════════ Lead Summary ══════════════════════════

class LeadSummaryPage extends StatefulWidget {
  const LeadSummaryPage({super.key});
  @override
  State<LeadSummaryPage> createState() => _LeadSummaryPageState();
}

class _LeadSummaryPageState extends State<LeadSummaryPage> {
  Rec? _summary;
  bool _loading = true;
  final _from = TextEditingController();
  final _to = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _from.dispose();
    _to.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await Api.one('/leads/summary', query: {
        if (_from.text.isNotEmpty) 'from': _from.text,
        if (_to.text.isNotEmpty) 'to': _to.text,
      });
      setState(() {
        _summary = res;
        _loading = false;
        _from.text = str(res['range']?['from'], _from.text);
        _to.text = str(res['range']?['to'], _to.text);
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _summary;
    return Scaffold(
      appBar: AppBar(title: const Text('Lead Summary')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : s == null
              ? Center(child: Text('Could not load summary', style: TextStyle(color: context.mutedColor)))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Row(children: [
                        Expanded(child: TextField(controller: _from, decoration: const InputDecoration(labelText: 'From (YYYY-MM-DD)', isDense: true))),
                        const SizedBox(width: 8),
                        Expanded(child: TextField(controller: _to, decoration: const InputDecoration(labelText: 'To (YYYY-MM-DD)', isDense: true))),
                        const SizedBox(width: 8),
                        IconButton(icon: const Icon(Icons.search_rounded), onPressed: _load),
                      ]),
                      const SizedBox(height: 16),
                      StatGrid([
                        ('All leads', '${s['totals']?['all'] ?? 0}', Icons.groups_rounded),
                        ('In range', '${s['totals']?['in_range'] ?? 0}', Icons.date_range_rounded),
                        ('New today', '${s['totals']?['new_today'] ?? 0}', Icons.fiber_new_rounded),
                        ('New this week', '${s['totals']?['new_week'] ?? 0}', Icons.calendar_view_week_rounded),
                        ('New this month', '${s['totals']?['new_month'] ?? 0}', Icons.calendar_month_rounded),
                        ('Unassigned', '${s['totals']?['unassigned'] ?? 0}', Icons.person_off_rounded),
                        ('Enrolled', '${s['totals']?['enrolled'] ?? 0}', Icons.check_circle_rounded),
                        ('Conversion', '${s['totals']?['conversion_rate'] ?? 0}%', Icons.trending_up_rounded),
                      ]),
                      const SizedBox(height: 20),
                      _BarSection(title: 'By stage', data: s['by_stage']),
                      _BarSection(title: 'By source', data: s['by_source']),
                      _BarSection(title: 'By priority', data: s['by_priority']),
                      if (s['by_agent'] is List && (s['by_agent'] as List).isNotEmpty) ...[
                        const SizedBox(height: 8),
                        const Text('By agent', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                        const SizedBox(height: 8),
                        ...(s['by_agent'] as List).whereType<Map>().map(
                              (a) => KvRow(str(a['agent']), '${a['total']}'),
                            ),
                      ],
                    ],
                  ),
                ),
    );
  }
}

class _BarSection extends StatelessWidget {
  const _BarSection({required this.title, required this.data});
  final String title;
  final dynamic data;

  @override
  Widget build(BuildContext context) {
    if (data is! Map || (data as Map).isEmpty) return const SizedBox.shrink();
    final entries = (data as Map).entries.toList()
      ..sort((a, b) => (num.tryParse('${b.value}') ?? 0).compareTo(num.tryParse('${a.value}') ?? 0));
    final max = entries.fold<num>(1, (m, e) => (num.tryParse('${e.value}') ?? 0) > m ? num.tryParse('${e.value}') ?? 0 : m);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 10),
          for (final e in entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('${e.key}', style: const TextStyle(fontSize: 13)),
                      Text('${e.value}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: (num.tryParse('${e.value}') ?? 0) / max,
                      minHeight: 6,
                      backgroundColor: context.altSurface,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

