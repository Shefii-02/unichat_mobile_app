import 'package:flutter/material.dart';
import 'package:unichat_mobile_app/features/message_sender/campaign_composer.dart';
import 'package:unichat_mobile_app/features/message_sender/campaign_history_tab.dart';

/// WA Chat's "Campaigns" quick link — mirrors
/// frontend/src/pages/wa-chat/pages/message-sender/index.tsx's "📨 Campaign" / "🕐 History" tabs.
/// Reached via the `/message-sender` route (AppModule id `message_sender`, WA Chat group) —
/// unrelated to the separate, generic `/campaigns` CRM feature.
class MessageSenderPage extends StatefulWidget {
  const MessageSenderPage({super.key});
  @override
  State<MessageSenderPage> createState() => _MessageSenderPageState();
}

enum _PageTab { campaign, history }

class _MessageSenderPageState extends State<MessageSenderPage> {
  _PageTab _tab = _PageTab.campaign;
  // Bumped after a successful send so the History tab (keyed on this) remounts and reloads —
  // simpler than wiring a shared refresh callback through to a widget that may not be built yet.
  int _historyRefreshTick = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Wa Campaigns')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: SegmentedButton<_PageTab>(
              segments: const [
                ButtonSegment(value: _PageTab.campaign, label: Text('📨 Campaign')),
                ButtonSegment(value: _PageTab.history, label: Text('🕐 History')),
              ],
              selected: {_tab},
              onSelectionChanged: (s) => setState(() => _tab = s.first),
            ),
          ),
          Expanded(
            child: IndexedStack(
              index: _tab == _PageTab.campaign ? 0 : 1,
              children: [
                CampaignComposer(
                  onSent: () => setState(() { _tab = _PageTab.history; _historyRefreshTick++; }),
                ),
                CampaignHistoryTab(key: ValueKey(_historyRefreshTick)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
