import "package:flutter/material.dart";
import "package:go_router/go_router.dart";
import "package:unichat_mobile_app/core/permissions/permission_guard.dart";
import "package:unichat_mobile_app/features/modules/_shared.dart";

// ══════════════════════════ Lead sources ══════════════════════════

/// Where leads come from this month: per source, how many arrived and where they stand, plus what waits for a check.
/// Tap a source for its leads. Backed by GET /leads/reports/sources.
class LeadSourcesPage extends StatefulWidget {
  const LeadSourcesPage({super.key});
  @override
  State<LeadSourcesPage> createState() => _LeadSourcesPageState();
}

class _LeadSourcesPageState extends State<LeadSourcesPage> {
  List<Rec> _rows = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await Api.raw.get('/leads/reports/sources');
      final d = res.data as Map<String, dynamic>;
      setState(() {
        _rows = ((d['rows'] as List?) ?? const []).whereType<Map<String, dynamic>>().toList();
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
      }
    }
  }

  Widget _stat(String label, Object? v, [Color? c]) => Expanded(
        child: Column(children: [
          Text('${v ?? 0}', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c)),
          Text(label, style: TextStyle(fontSize: 10, color: context.mutedColor)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final canReview = PermissionGuard.can('leads.manage');
    return Scaffold(
      appBar: AppBar(title: const Text('Lead sources')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _rows.isEmpty
              ? Center(child: Text('No leads this month', style: TextStyle(color: context.mutedColor)))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: _rows.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final r = _rows[i];
                      final waiting = (r['awaiting_review'] as num?)?.toInt() ?? 0;
                      return Card(
                        child: InkWell(
                          onTap: () => context.push('/leads-by-source/${r['source']}?name=${Uri.encodeComponent(str(r['label']))}'),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                Text('${r['icon'] ?? '•'}  ', style: const TextStyle(fontSize: 18)),
                                Expanded(child: Text(str(r['label']), style: const TextStyle(fontWeight: FontWeight.w700))),
                                Text('${r['conversion'] ?? 0}% converted', style: TextStyle(fontSize: 11, color: context.mutedColor)),
                              ]),
                              const SizedBox(height: 8),
                              Row(children: [
                                _stat('Leads', r['total']),
                                _stat('New', r['new']),
                                _stat('Follow-up', r['in_followup'], Colors.amber.shade800),
                                _stat('Converted', r['converted'], Colors.green.shade700),
                                _stat('Lost', r['lost'], Colors.red.shade600),
                              ]),
                              if (canReview && waiting > 0)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: ActionChip(
                                    avatar: const Icon(Icons.fact_check_outlined, size: 16),
                                    label: Text('$waiting waiting for a check'),
                                    onPressed: () => context.push('/lead-review'),
                                  ),
                                ),
                            ]),
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
