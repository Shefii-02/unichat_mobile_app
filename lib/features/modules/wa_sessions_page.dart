// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:unichat_mobile_app/core/network/wa_chat_api_service.dart';
import 'package:unichat_mobile_app/core/widgets/app_empty_state.dart';
import 'package:unichat_mobile_app/features/auth/presentation/providers/auth_provider.dart';
import 'wa_chat_api.dart';
import 'wa_chat_extra_pages.dart' show WaContactsPage;
import '_shared.dart';

/// WA Chat's "Sessions" — mirrors frontend/src/pages/wa-chat/pages/Sessions.tsx: list and every
/// per-session action (start/stop/logout/force-kill/QR/pairing-code/delete) go straight to the
/// open-wa gateway with the company's own scoped `wa_chat_token`, verified against the gateway's
/// own guards to carry no @RequireUnscopedKey() fence. Two things stay Laravel-proxied instead,
/// deliberately NOT mirroring the web app (which calls these same two on the gateway too, and —
/// per that investigation — would 403 for every real company since they need Laravel's own
/// resources, not the gateway's):
///   - creating a session (`WaChatApi.createSession`) — the gateway's `POST /sessions` requires
///     an UNSCOPED key, which a company's own scoped token can never be; only Laravel holds the
///     real admin key, server-side only.
///   - "WA Contacts" / "Sync WA labels to CRM" — these write into Flowexa's own CRM tables
///     (`Contact`, `ContactLabel`), a Laravel-side concept the gateway has no notion of at all.
/// Laravel's own session list (`WaChatApi.sessions()`) is still fetched alongside the gateway's,
/// purely to cross-reference `display_name` (gateway sessions are named an opaque
/// `co{companyId}-{random}` slug — see WahaSessionController::store — so the gateway's own `name`
/// field is useless for display) and the Laravel numeric row id those two CRM actions key on.
class WaSessionsPage extends ConsumerStatefulWidget {
  const WaSessionsPage({super.key});
  @override
  ConsumerState<WaSessionsPage> createState() => _WaSessionsPageState();
}

class _WaSessionsPageState extends ConsumerState<WaSessionsPage> {
  List<Rec> _sessions = [];
  bool _loading = true;
  String? _error;
  bool _reconnecting = false;
  String? _apiKeyOverride;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  String? get _apiKey => _apiKeyOverride ?? ref.read(authProvider).value?.waContactToken;

  Future<void> _load() async {
    final key = _apiKey;
    if (key == null || key.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'This company has no WhatsApp gateway token configured yet.';
      });
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final gatewaySessions = await WaChatApiService.getSessions(key);
      List<Rec> laravelRows = [];
      try {
        laravelRows = await WaChatApi.sessions();
      } catch (_) {
        // Best-effort: without this, sessions just show their raw gateway id instead of the
        // display name the user picked, and lose the "WA Contacts"/"Sync labels" actions.
      }
      final byGatewayId = {
        for (final row in laravelRows) str(row['session_name'], ''): row,
      };
      final merged = gatewaySessions.map((s) {
        final row = byGatewayId[str(s['id'], '')];
        return {
          ...s,
          'laravelId': row?['id'],
          'displayName': row?['display_name'],
        };
      }).toList();
      if (!mounted) return;
      setState(() { _sessions = merged; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      // Deliberately NOT auto-reconnected on a 401 — reconnecting mints a fresh gateway key and
      // REVOKES THE OLD ONE (WaChatTokenService::provision), and that key is shared by every
      // client on the company's account (the web app, other devices, ...). Auto-firing it here
      // the moment this one page sees a transient 401 would kick every other concurrently-open
      // client off. Leave it to the manual "Reconnect WA Chat" button.
      setState(() { _loading = false; _error = apiErrorMessage(e); });
    }
  }

  Future<void> _reconnect() async {
    setState(() => _reconnecting = true);
    try {
      final res = await WaChatApi.reconnectToken();
      final key = res['wa_chat_token'] as String?;
      if (key == null || key.isEmpty) throw Exception('Gateway did not return a key.');
      if (!mounted) return;
      setState(() { _apiKeyOverride = key; _reconnecting = false; });
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _reconnecting = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Couldn't reconnect — ${apiErrorMessage(e)}")));
    }
  }

  String _label(Rec s) {
    final displayName = str(s['displayName'], '');
    if (displayName.isNotEmpty) return displayName;
    return str(s['phone'], 'Session');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sessions')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _newSession(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New session'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? AppEmptyState(
                  icon: Icons.error_outline,
                  title: "Couldn't load sessions",
                  subtitle: _error,
                  action: TextButton(
                    onPressed: _reconnecting ? null : _reconnect,
                    child: _reconnecting
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Reconnect WA Chat'),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _sessions.isEmpty
                      ? ListView(children: const [
                          SizedBox(height: 80),
                          AppEmptyState(icon: Icons.smartphone_rounded, title: 'No WhatsApp sessions'),
                        ])
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: _sessions.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (context, i) => _sessionTile(_sessions[i]),
                        ),
                ),
    );
  }

  Widget _sessionTile(Rec s) {
    final status = str(s['status'], '');
    final connected = status == 'ready';
    final laravelId = s['laravelId'] as int?;

    return RecordCard(
      title: _label(s),
      subtitle: '${str(s['phone'], 'No number')} · ${str(status, 'unknown')}',
      leadingIcon: connected ? Icons.check_circle_rounded : Icons.qr_code_rounded,
      leadingColor: connected ? AppPalette.success : AppPalette.warning,
      onTap: connected ? null : () => _showQr(s),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          StatusPill(status.isEmpty ? 'unknown' : status),
          RowMenu(items: [
            if (connected && laravelId != null)
              (
                'WA Contacts',
                Icons.contacts_rounded,
                () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => WaContactsPage(sessionId: laravelId, sessionLabel: _label(s)),
                    )),
              ),
            if (connected && laravelId != null)
              (
                'Sync WA labels to CRM',
                Icons.label_rounded,
                () => runAction(context,
                    () => WaChatApi.syncLabelsToCrm(laravelId),
                    success: 'Labels synced — see them under Labels.'),
              ),
            if (!connected)
              (
                'Start',
                Icons.play_arrow_rounded,
                () => _act(s, (id, key) => WaChatApiService.startSession(id, key), success: 'Starting…'),
              )
            else
              (
                'Stop',
                Icons.stop_rounded,
                () => _act(s, (id, key) => WaChatApiService.stopSession(id, key), success: 'Stopping…'),
              ),
            if (!connected)
              ('Show QR', Icons.qr_code_rounded, () => _showQr(s)),
            if (!connected)
              ('Pairing code', Icons.dialpad_rounded, () => _requestPairingCode(s)),
            (
              'Log out',
              Icons.logout_rounded,
              () => _act(s, (id, key) => WaChatApiService.logoutSession(id, key), success: 'Logged out'),
            ),
            (
              'Force kill',
              Icons.power_off_rounded,
              () async {
                if (!await confirm(context,
                    title: 'Force-kill this session?',
                    message: 'Only use this if the session is stuck and Stop/Log out '
                        "aren't responding — it hard-kills the engine.",
                    destructive: true,
                    confirmLabel: 'Force kill')) { return; }
                await _act(s, (id, key) => WaChatApiService.forceKillSession(id, key),
                    success: 'Session force-killed.');
              },
            ),
            (
              'Delete',
              Icons.delete_rounded,
              () async {
                if (!await confirm(context, title: 'Delete session?', destructive: true, confirmLabel: 'Delete')) {
                  return;
                }
                await _act(s, (id, key) => WaChatApiService.deleteSession(id, key), success: 'Deleted');
              },
            ),
          ]),
        ],
      ),
    );
  }

  Future<void> _act(Rec s, Future<void> Function(String id, String key) call, {String? success}) async {
    final key = _apiKey;
    final id = str(s['id'], '');
    if (key == null || key.isEmpty || id.isEmpty) return;
    final ok = await runAction(context, () => call(id, key), success: success);
    if (ok) await _load();
  }

  Future<void> _showQr(Rec s) async {
    final key = _apiKey;
    final id = str(s['id'], '');
    if (key == null || id.isEmpty) return;
    Rec qr;
    try {
      qr = await WaChatApiService.sessionQr(id, key);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
      }
      return;
    }
    if (!context.mounted) return;
    final value = qr['qrCode'] ?? qr['qr'] ?? qr['value'] ?? qr['data'];
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Scan with WhatsApp',
                style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            if (value is String && value.startsWith('data:image'))
              Image.memory(Uri.parse(value).data!.contentAsBytes(), width: 240, height: 240)
            else if (value != null)
              SelectableText('$value', style: const TextStyle(fontFamily: 'monospace'))
            else
              Text('QR not available — try Start first', style: TextStyle(color: ctx.mutedColor)),
          ],
        ),
      ),
    );
  }

  /// Alternative to scanning a QR (see [_showQr]) — the gateway issues an 8-char code the
  /// user types into WhatsApp's own "Link with phone number" flow instead.
  Future<void> _requestPairingCode(Rec s) async {
    final key = _apiKey;
    final id = str(s['id'], '');
    if (key == null || id.isEmpty) return;
    final phoneCtrl = TextEditingController();
    final phone = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Request pairing code'),
        content: TextField(
          controller: phoneCtrl,
          autofocus: true,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: 'Phone number (with country code)',
            hintText: 'e.g. 628123456789',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, phoneCtrl.text.trim()), child: const Text('Request')),
        ],
      ),
    );
    if (phone == null || phone.isEmpty || !context.mounted) return;

    Rec res;
    try {
      res = await WaChatApiService.requestPairingCode(id, key, phone);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
      }
      return;
    }
    if (!context.mounted) return;
    final code = res['pairingCode'] ?? res['code'] ?? res['value'];
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pairing code'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Enter this code in WhatsApp → Linked devices → Link with phone number:',
                style: TextStyle(color: ctx.mutedColor, fontSize: 13)),
            const SizedBox(height: 12),
            SelectableText('$code', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: 4)),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Done'))],
      ),
    );
  }

  /// Session creation is Laravel-only — the gateway requires an unscoped ADMIN key to mint a
  /// session at all, which a company's own scoped token can never be (see the class doc comment).
  Future<void> _newSession(BuildContext context) async {
    final data = <String, dynamic>{};
    final ok = await showFormSheet(
      context,
      title: 'New WhatsApp session',
      submitLabel: 'Create',
      fields: (ctx) => [
        // WahaSessionController::store() validates `display_name`, not `name` — sending `name`
        // here was a pre-existing bug that silently dropped the label the user just typed (the
        // Laravel row's display_name always ended up null, and the gateway session got an opaque
        // co{companyId}-{random} name instead — see this page's class doc comment).
        FText(label: 'Session name', required: true, hint: 'e.g. Sales line', onSaved: (v) => data['display_name'] = v),
      ],
      onSubmit: () => WaChatApi.createSession(data),
    );
    if (ok) _load();
  }
}
