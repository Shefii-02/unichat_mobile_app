import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:unichat_mobile_app/features/modules/module_providers.dart";
import "package:unichat_mobile_app/features/modules/_shared.dart";

// ══════════════════════════ Lead Intelligence ══════════════════════════

class LeadIntelligencePage extends ConsumerStatefulWidget {
  const LeadIntelligencePage({super.key});
  @override
  ConsumerState<LeadIntelligencePage> createState() => _LeadIntelligencePageState();
}

class _LeadIntelligencePageState extends ConsumerState<LeadIntelligencePage> {
  List<Rec> _contacts = [];
  bool _loading = true;
  String? _stage;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rows = await Api.list('/meta-ai/lead-scores', query: {
        if (_stage != null) 'stage': _stage,
      });
      setState(() { _contacts = rows; _loading = false; });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final statsAsync = ref.watch(metaAiStatsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Lead Intelligence')),
      body: RefreshIndicator(
        onRefresh: () async { ref.invalidate(metaAiStatsProvider); await _load(); },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            statsAsync.when(
              loading: () => const SizedBox(height: 80, child: Center(child: CircularProgressIndicator())),
              error: (e, _) => Text("Couldn't load stats — ${apiErrorMessage(e)}", style: TextStyle(color: context.mutedColor)),
              data: (s) => StatGrid([
                ('Analyzed', '${s['total_analyzed'] ?? 0}', Icons.psychology_rounded),
                ('Avg score', '${s['avg_lead_score'] ?? 0}', Icons.speed_rounded),
                ('Hot leads', '${s['hot_leads'] ?? 0}', Icons.local_fire_department_rounded),
                ('Conversions (mo)', '${s['conversions_month'] ?? 0}', Icons.emoji_events_rounded),
              ]),
            ),
            const SizedBox(height: 16),
            Wrap(spacing: 6, children: [
              ChoiceChip(label: const Text('All'), selected: _stage == null, onSelected: (_) { setState(() => _stage = null); _load(); }),
              for (final s in ['new', 'contacted', 'follow_up', 'enrolled', 'lost'])
                ChoiceChip(label: Text(s), selected: _stage == s, onSelected: (_) { setState(() => _stage = s); _load(); }),
            ]),
            const SizedBox(height: 12),
            if (_loading)
              const Padding(padding: EdgeInsets.only(top: 40), child: Center(child: CircularProgressIndicator()))
            else if (_contacts.isEmpty)
              Padding(padding: const EdgeInsets.only(top: 40), child: Center(child: Text('No analyzed contacts', style: TextStyle(color: context.mutedColor))))
            else
              ..._contacts.map((c) {
                final score = num.tryParse('${c['lead_score'] ?? 0}') ?? 0;
                return RecordCard(
                  title: str(c['name'], c['phone']),
                  subtitle: '${str(c['detected_intent'], 'unknown')} · ${str(c['last_sentiment'], 'neutral')} · ${str(c['score_label'], '')}',
                  leadingIcon: Icons.person_rounded,
                  leadingColor: score >= 70 ? AppPalette.danger : score >= 40 ? AppPalette.warning : AppPalette.info,
                  trailing: Text('${score.toInt()}', style: const TextStyle(fontWeight: FontWeight.w800)),
                  onTap: () => _showIntelligence(context, c),
                );
              }),
          ],
        ),
      ),
    );
  }

  Future<void> _showIntelligence(BuildContext context, Rec contact) async {
    Rec? detail;
    String? error;
    try {
      detail = await Api.one('/contacts/${contact['id']}/intelligence');
    } catch (e) {
      error = apiErrorMessage(e);
    }
    if (!context.mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        builder: (ctx, scrollController) => ListView(
          controller: scrollController,
          padding: const EdgeInsets.all(20),
          children: error != null
              ? [Text(error)]
              : [
                  Text(str(contact['name'], contact['phone']), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                  const SizedBox(height: 12),
                  KvRow('Lead score', '${detail?['lead_score'] ?? '—'} (${str(detail?['lead_score_label'], '')})'),
                  KvRow('Sentiment', str(detail?['last_sentiment'])),
                  KvRow('Intent', str(detail?['detected_intent'])),
                  KvRow('Buying signals', '${detail?['buying_signals_count'] ?? 0}'),
                  KvRow('Objections', '${detail?['objections_count'] ?? 0}'),
                  const SizedBox(height: 12),
                  if (detail?['conversation_summary'] != null) ...[
                    const Text('Summary', style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(str(detail?['conversation_summary'])),
                    const SizedBox(height: 12),
                  ],
                  if (detail?['recommended_next_action'] != null) ...[
                    const Text('Recommended next action', style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(str(detail?['recommended_next_action'])),
                  ],
                ],
        ),
      ),
    );
  }
}

