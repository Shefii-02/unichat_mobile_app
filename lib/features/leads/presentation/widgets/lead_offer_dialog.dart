import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:unichat_mobile_app/core/network/api.dart';

/// The app-side twin of the web popups: "🤖 AI Agent Offer" (take over an AI-handled chat) and "🎯 New lead offered" (accept / decline).
/// [d] is the push payload: action = ai_handoff_offer | lead_offer, assignment_id, contact_name, contact_phone, …
Future<void> showLeadOfferDialog(BuildContext context, Map<String, dynamic> d) {
  return showDialog<void>(context: context, barrierDismissible: true, builder: (_) => _OfferCard(d: d));
}

class _OfferCard extends StatefulWidget {
  const _OfferCard({required this.d});
  final Map<String, dynamic> d;
  @override
  State<_OfferCard> createState() => _OfferCardState();
}

class _OfferCardState extends State<_OfferCard> {
  bool _busy = false;

  bool get _ai => widget.d['action'] == 'ai_handoff_offer';

  /// The last few messages, sent with the push as JSON text: [{from: customer|ai|staff, text}]
  List<Map<String, dynamic>> get _messages {
    final raw = widget.d['messages'];
    try {
      final list = raw is String ? jsonDecode(raw) : raw;
      return [for (final m in (list as List? ?? const [])) if (m is Map && '${m['text']}'.trim().isNotEmpty) Map<String, dynamic>.from(m)];
    } catch (_) {
      return const [];
    }
  }

  /// One chat bubble: the customer on the left, the AI / our team on the right.
  Widget _bubble(BuildContext context, Map<String, dynamic> m) {
    final customer = m['from'] == 'customer';
    final ai = m['from'] == 'ai';
    return Align(
      alignment: customer ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        constraints: const BoxConstraints(maxWidth: 250),
        decoration: BoxDecoration(
          color: customer ? Theme.of(context).colorScheme.surface : (ai ? Colors.purple : Colors.blue.shade700),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(customer ? 4 : 16),
            bottomRight: Radius.circular(customer ? 16 : 4),
          ),
          border: customer ? Border.all(color: Colors.black12) : null,
        ),
        child: Text('${m['text']}', style: TextStyle(fontSize: 13, color: customer ? null : Colors.white)),
      ),
    );
  }

  Future<void> _respond(bool accept) async {
    final id = int.tryParse('${widget.d['assignment_id']}');
    if (id == null) return;
    setState(() => _busy = true);
    try {
      await Api.post('/lead-assignments/$id/${accept ? 'accept' : 'decline'}');
      if (!mounted) return;
      final router = GoRouter.of(context);
      final widgetChat = int.tryParse('${widget.d['widget_conversation_id']}');
      Navigator.of(context).pop();
      // taking over a website-widget chat opens that chat
      final leadId = int.tryParse('${widget.d['lead_id']}');
      if (accept && _ai) {
        if (widgetChat != null) {
          router.push('/wa-agent/widget-chats?c=$widgetChat');
        } else if (leadId != null) {
          router.push('/lead-detail/$leadId');   // any other channel: the lead page has the whole chat
        }
      }
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
        content: Text(accept ? (_ai ? "You're taking over the conversation!" : 'Lead accepted.') : (_ai ? 'AI keeps the conversation.' : 'Lead declined.')),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.d;
    final name = '${d['contact_name'] ?? 'Unknown'}';
    final phone = '${d['contact_phone'] ?? ''}';
    final summary = '${d['conversation_summary'] ?? ''}';
    final theme = Theme.of(context);
    final color = _ai ? Colors.purple : theme.colorScheme.primary;
    return AlertDialog(
      titlePadding: EdgeInsets.zero,
      title: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(color: color, borderRadius: const BorderRadius.vertical(top: Radius.circular(28))),
        child: Text(_ai ? '🤖 AI Agent Offer' : '🎯 New lead offered', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
      ),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_ai ? "I'm currently chatting with:" : 'Offered to you:', style: TextStyle(fontSize: 12, color: theme.hintColor)),
        const SizedBox(height: 4),
        Text('👤 $name', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        if (phone.isNotEmpty) Text('📱 $phone', style: TextStyle(color: theme.hintColor)),
        if (_ai && _messages.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxHeight: 210),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: Colors.purple.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
            child: SingleChildScrollView(
              child: Column(children: [for (final m in _messages) _bubble(context, m)]),
            ),
          ),
        ] else if (_ai && summary.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.purple.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
            child: Text('"$summary"', style: const TextStyle(fontStyle: FontStyle.italic)),
          ),
        ],
        const SizedBox(height: 12),
        Text(_ai ? 'Want to take over this conversation?' : 'Accept this lead?', style: const TextStyle(fontWeight: FontWeight.w600)),
      ]),
      actions: [
        TextButton(onPressed: _busy ? null : () => _respond(false), child: Text(_ai ? 'No, keep AI' : 'Decline')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: color),
          onPressed: _busy ? null : () => _respond(true),
          child: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Text(_ai ? "Yes, I'll take it 👋" : 'Accept'),
        ),
      ],
    );
  }
}
