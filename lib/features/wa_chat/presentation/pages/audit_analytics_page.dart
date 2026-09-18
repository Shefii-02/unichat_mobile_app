// ignore_for_file: use_build_context_synchronously
import "dart:io";
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:path_provider/path_provider.dart";
import "package:share_plus/share_plus.dart";
import "package:unichat_mobile_app/features/modules/wa_chat_api.dart";
import "package:unichat_mobile_app/features/modules/_shared.dart";

// ══════════════════════════ Audit Logs ══════════════════════════
// Mirrors frontend/src/pages/wa-chat/pages/Logs.tsx (the OpenWA gateway's own audit trail),
// but reads it through Laravel's `GET /waha/audit` rather than the gateway directly: the
// gateway's `/audit` route requires an ADMIN-role, unscoped key, which a company's own
// `wa_chat_token` is never minted as (see WaChatApi.auditLog / WahaSessionController::auditLog
// on the Laravel side). Laravel fans the query out over this company's sessions with the
// gateway's admin key instead, so no gateway-side permission change is needed here.

const _auditSeverities = ['info', 'warn', 'error'];
const _pageLimit = 20;

class AuditAnalyticsPage extends ConsumerStatefulWidget {
  const AuditAnalyticsPage({super.key});
  @override
  ConsumerState<AuditAnalyticsPage> createState() => _AuditAnalyticsPageState();
}

class _AuditAnalyticsPageState extends ConsumerState<AuditAnalyticsPage> {
  List<Rec> _rows = [];
  int _total = 0;
  int _page = 1;
  bool _loading = true;
  bool _exporting = false;
  String? _error;
  String? _severity;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await WaChatApi.auditLog(severity: _severity, limit: _pageLimit, offset: (_page - 1) * _pageLimit);
      final rows = res['data'];
      setState(() {
        _rows = rows is List ? rows.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList() : [];
        _total = (res['total'] as num?)?.toInt() ?? _rows.length;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = apiErrorMessage(e);
      });
    }
  }

  List<Rec> get _filteredRows {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return _rows;
    return _rows.where((r) => str(r['action'], '').toLowerCase().contains(q) || str(r['errorMessage'], '').toLowerCase().contains(q)).toList();
  }

  int get _totalPages => (_total / _pageLimit).ceil().clamp(1, 1 << 30);

  Future<void> _exportCsv() async {
    if (_total == 0 || _exporting) return;
    setState(() => _exporting = true);
    try {
      // Paginate through the gateway-backed endpoint up to a safety cap, honouring the active
      // severity filter (search stays client-side, applied after fetching — the API has no
      // text-search param), mirroring Logs.tsx's handleExportCsv.
      final all = <Rec>[];
      var offset = 0;
      const cap = 2000;
      while (all.length < _total && all.length < cap) {
        final res = await WaChatApi.auditLog(severity: _severity, limit: 200, offset: offset);
        final page = res['data'];
        final batch = page is List ? page.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList() : <Rec>[];
        if (batch.isEmpty) break;
        all.addAll(batch);
        offset += batch.length;
      }
      final q = _searchCtrl.text.trim().toLowerCase();
      final rows = q.isEmpty
          ? all
          : all.where((r) => str(r['action'], '').toLowerCase().contains(q) || str(r['errorMessage'], '').toLowerCase().contains(q)).toList();
      if (rows.isEmpty) return;

      final headers = ['timestamp', 'action', 'severity', 'session', 'apiKey', 'ip', 'method', 'path', 'statusCode', 'errorMessage'];
      final lines = [headers.join(',')];
      for (final r in rows) {
        lines.add([
          str(r['createdAt'], ''),
          str(r['action'], ''),
          str(r['severity'], ''),
          str(r['sessionName'] ?? r['sessionId'], ''),
          str(r['apiKeyName'] ?? r['apiKeyId'], ''),
          str(r['ipAddress'], ''),
          str(r['method'], ''),
          str(r['path'], ''),
          str(r['statusCode'], ''),
          str(r['errorMessage'], ''),
        ].map(_csvCell).join(','));
      }
      final csv = lines.join('\n');
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/openwa-audit-logs-${DateTime.now().millisecondsSinceEpoch}.csv');
      await file.writeAsString(csv);
      if (mounted) await Share.shareXFiles([XFile(file.path)], text: 'WA Chat audit logs export');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  String _csvCell(String v) {
    if (v.contains(',') || v.contains('"') || v.contains('\n')) {
      return '"${v.replaceAll('"', '""')}"';
    }
    return v;
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredRows;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Audit Logs'),
        actions: [
          IconButton(
            tooltip: 'Export CSV',
            onPressed: (_exporting || _total == 0) ? null : _exportCsv,
            icon: _exporting
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.download_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search_rounded, size: 18),
                hintText: 'Search action or error…',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: const Text('All'),
                    selected: _severity == null,
                    onSelected: (_) { setState(() { _severity = null; _page = 1; }); _load(); },
                  ),
                ),
                for (final s in _auditSeverities)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(s),
                      selected: _severity == s,
                      onSelected: (_) { setState(() { _severity = s; _page = 1; }); _load(); },
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Padding(
                        padding: const EdgeInsets.all(24),
                        child: Center(child: Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: context.mutedColor))),
                      )
                    : filtered.isEmpty
                        ? Center(
                            child: Text(
                              _searchCtrl.text.trim().isNotEmpty || _severity != null ? 'No logs match this filter' : 'No audit events',
                              style: TextStyle(color: context.mutedColor),
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.separated(
                              padding: const EdgeInsets.all(12),
                              itemCount: filtered.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 8),
                              itemBuilder: (_, i) => _logCard(filtered[i]),
                            ),
                          ),
          ),
          if (_totalPages > 1)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    onPressed: (_page > 1 && !_loading) ? () { setState(() => _page--); _load(); } : null,
                    icon: const Icon(Icons.chevron_left_rounded),
                  ),
                  Text('Page $_page of $_totalPages', style: TextStyle(fontSize: 12, color: context.mutedColor)),
                  IconButton(
                    onPressed: (_page < _totalPages && !_loading) ? () { setState(() => _page++); _load(); } : null,
                    icon: const Icon(Icons.chevron_right_rounded),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _logCard(Rec row) {
    return RecordCard(
      title: str(row['action'], 'event'),
      subtitle: [
        if (str(row['sessionName'] ?? row['sessionId'], '').isNotEmpty) row['sessionName'] ?? row['sessionId'],
        if (str(row['apiKeyName'], '').isNotEmpty) 'key: ${row['apiKeyName']}',
        if (row['method'] != null && row['path'] != null) '${row['method']} ${row['path']}',
        if (row['statusCode'] != null) 'HTTP ${row['statusCode']}',
        if (str(row['ipAddress'], '').isNotEmpty) row['ipAddress'],
        if (str(row['errorMessage'], '').isNotEmpty) row['errorMessage'],
        when(row['createdAt']),
      ].join(' · '),
      leadingIcon: Icons.fact_check_rounded,
      trailing: StatusPill(str(row['severity'], 'info')),
    );
  }
}
