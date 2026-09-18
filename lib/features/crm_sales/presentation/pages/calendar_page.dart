// ignore_for_file: use_build_context_synchronously
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:unichat_mobile_app/features/modules/module_providers.dart";
import "package:unichat_mobile_app/features/modules/_shared.dart";

// ══════════════════════════ Calendar ══════════════════════════

class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});
  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  List<Rec> _events = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await Api.one('/crm/calendar-events');
      final events = res['events'];
      setState(() {
        _events = events is List ? events.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList() : [];
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    _events.sort((a, b) => str(a['starts_at']).compareTo(str(b['starts_at'])));
    return Scaffold(
      appBar: AppBar(title: const Text('Calendar')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _book(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Book'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _events.isEmpty
                  ? ListView(children: [
                      const SizedBox(height: 120),
                      Icon(Icons.event_available_outlined, size: 56, color: context.mutedColor),
                      const SizedBox(height: 12),
                      Center(child: Text('No upcoming events', style: TextStyle(color: context.mutedColor))),
                    ])
                  : ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: _events.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) => _EventCard(event: _events[i], onChanged: _load),
                    ),
            ),
    );
  }

  Future<void> _book(BuildContext context) async {
    List<Rec> contacts;
    List<Rec> staff;
    try {
      contacts = await Api.list('/contacts', query: {'per_page': 100});
      staff = await Api.list('/staff');
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
      return;
    }
    if (!context.mounted) return;
    final data = <String, dynamic>{'type': 'appointment'};
    final ok = await showFormSheet(
      context,
      title: 'Book event',
      fields: (ctx) => [
        FText(label: 'Title', required: true, onSaved: (v) => data['title'] = v),
        FSelect<String>(label: 'Type', options: const ['appointment', 'followup', 'callback', 'meeting'],
            initial: 'appointment', onSaved: (v) => data['type'] = v ?? 'appointment'),
        FText(label: 'Starts (YYYY-MM-DD HH:mm)', required: true, hint: '2026-09-20 14:00', onSaved: (v) => data['starts_at'] = v),
        FText(label: 'Ends (YYYY-MM-DD HH:mm)', required: true, hint: '2026-09-20 15:00', onSaved: (v) => data['ends_at'] = v),
        FText(label: 'Location', onSaved: (v) => v.isEmpty ? null : data['location'] = v),
        if (contacts.isNotEmpty)
          FSelect<Rec>(label: 'Contact (optional)', options: contacts,
              labelOf: (c) => '${c['name'] ?? c['phone']}', onSaved: (c) => data['contact_id'] = c?['id']),
        FSelect<Rec>(label: 'Assign to (optional)', options: staff, labelOf: (s) => str(s['name']),
            onSaved: (s) => data['assigned_to'] = s?['id']),
      ],
      onSubmit: () => Api.post('/crm/calendar-events', data: data),
    );
    if (ok) _load();
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({required this.event, required this.onChanged});
  final Rec event;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final status = str(event['status'], 'scheduled');
    final contact = (event['contact'] is Map) ? (event['contact'] as Map) : const {};
    return RecordCard(
      title: str(event['title']),
      subtitle: '${str(event['type'], 'appointment')} · ${when(event['starts_at'])}'
          '${contact['name'] != null ? ' · ${contact['name']}' : ''}',
      leadingIcon: Icons.event_rounded,
      trailing: status == 'scheduled'
          ? RowMenu(items: [
              ('Complete', Icons.check_circle_outline_rounded, () async {
                final ok = await runAction(context, () => Api.post('/crm/calendar-events/${event['id']}/complete'), success: 'Marked completed');
                if (ok) onChanged();
              }),
              ('No-show', Icons.person_off_outlined, () async {
                final ok = await runAction(context, () => Api.post('/crm/calendar-events/${event['id']}/no-show'), success: 'Marked no-show');
                if (ok) onChanged();
              }),
              ('Cancel', Icons.close_rounded, () async {
                final sure = await confirm(context, title: 'Cancel this event?', destructive: true, confirmLabel: 'Cancel event');
                if (!sure) return;
                final ok = await runAction(context, () => Api.delete('/crm/calendar-events/${event['id']}'), success: 'Cancelled');
                if (ok) onChanged();
              }),
            ])
          : StatusPill(status),
    );
  }
}

