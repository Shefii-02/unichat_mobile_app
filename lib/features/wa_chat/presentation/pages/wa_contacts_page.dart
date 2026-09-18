// ignore_for_file: use_build_context_synchronously
import "dart:async";
import "package:dio/dio.dart";
import "package:fl_chart/fl_chart.dart";
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:go_router/go_router.dart";
import "package:url_launcher/url_launcher.dart";
import "package:unichat_mobile_app/core/network/wa_chat_api_service.dart";
import "package:unichat_mobile_app/core/widgets/app_empty_state.dart";
import "package:unichat_mobile_app/features/auth/presentation/providers/auth_provider.dart";
import "package:unichat_mobile_app/features/modules/module_providers.dart";
import "package:unichat_mobile_app/features/modules/wa_chat_api.dart";
import "package:unichat_mobile_app/features/modules/_shared.dart";

// ══════════════════════════ WA Contacts (per session) ══════════════════════════

/// One session's WhatsApp contacts (see docs.open-wa.org/api-reference/contacts) — each row
/// syncs into this company's own CRM contacts with a single tap (`Contact.wa_id`/`phone`),
/// or a "Sync all" pass does every contact at once. Reached from a session's row menu on the
/// Sessions page.
class WaContactsPage extends StatefulWidget {
  const WaContactsPage({super.key, required this.sessionId, required this.sessionLabel});
  final int sessionId;
  final String sessionLabel;

  @override
  State<WaContactsPage> createState() => _WaContactsPageState();
}

class _WaContactsPageState extends State<WaContactsPage> {
  List<Rec> _contacts = [];
  bool _loading = true;
  String? _error;
  final Set<String> _syncing = {};
  bool _syncingAll = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final rows = await WaChatApi.sessionContacts(widget.sessionId);
      if (!mounted) return;
      setState(() { _contacts = rows; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = apiErrorMessage(e); _loading = false; });
    }
  }

  String _cid(Rec c) => str(c['id'] ?? c['_serialized'] ?? c['contactId'] ?? c['number'], '');
  String _cname(Rec c) => str(c['name'] ?? c['pushname'] ?? c['formattedName'] ?? c['shortName'], 'Unknown');
  String _cphone(Rec c) {
    final raw = str(c['number'] ?? _cid(c), '');
    return raw.split('@').first;
  }

  Future<void> _syncOne(Rec c) async {
    final id = _cid(c);
    if (id.isEmpty) return;
    setState(() => _syncing.add(id));
    try {
      await WaChatApi.syncContact(widget.sessionId, id);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Synced to CRM contacts.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
      }
    } finally {
      if (mounted) setState(() => _syncing.remove(id));
    }
  }

  Future<void> _syncAll() async {
    setState(() => _syncingAll = true);
    try {
      final res = await WaChatApi.syncAllContacts(widget.sessionId);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(str(res['message'], 'Sync complete.'))));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
      }
    } finally {
      if (mounted) setState(() => _syncingAll = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${widget.sessionLabel} · Contacts')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _syncingAll ? null : _syncAll,
        icon: _syncingAll
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.sync_rounded),
        label: const Text('Sync all to CRM'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? AppEmptyState(icon: Icons.error_outline, title: "Couldn't load contacts", subtitle: _error)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _contacts.isEmpty
                      ? ListView(children: const [
                          SizedBox(height: 80),
                          AppEmptyState(icon: Icons.contacts_rounded, title: 'No WhatsApp contacts found'),
                        ])
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: _contacts.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (_, i) {
                            final c = _contacts[i];
                            final id = _cid(c);
                            final syncing = _syncing.contains(id);
                            return RecordCard(
                              title: _cname(c),
                              subtitle: _cphone(c),
                              leadingIcon: Icons.person_rounded,
                              trailing: syncing
                                  ? const SizedBox(
                                      width: 20, height: 20,
                                      child: CircularProgressIndicator(strokeWidth: 2))
                                  : IconButton(
                                      icon: const Icon(Icons.sync_rounded),
                                      tooltip: 'Sync to CRM',
                                      onPressed: id.isEmpty ? null : () => _syncOne(c),
                                    ),
                            );
                          },
                        ),
                ),
    );
  }
}

