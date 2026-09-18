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

// ══════════════════════════ Dashboard ══════════════════════════
// Mirrors frontend/src/pages/wa-chat/pages/Dashboard.tsx: sessions + session-stats + webhooks
// straight from the gateway with the company's own scoped key (all three are readable by an
// OPERATOR-role key), plus /api/stats/overview and /api/stats/messages, which degrade rather
// than failing the whole page if a future guard change ever makes either admin-only.

const _dashboardPeriods = ['24h', '7d', '30d'];

/// Stable, distinct color per message type — mirrors DashboardCharts.tsx's TYPE_COLORS so the
/// pie legend reads the same on both platforms. Falls back to a deterministic name hash for any
/// type not in this map, so an unmapped type still gets a stable color across rebuilds.
const _typeColors = <String, Color>{
  'text': Color(0xFF25D366),
  'image': Color(0xFF3B82F6),
  'contact': Color(0xFFA855F7),
  'document': Color(0xFFF59E0B),
  'audio': Color(0xFF06B6D4),
  'voice': Color(0xFFEC4899),
  'video': Color(0xFF14B8A6),
  'sticker': Color(0xFFEF4444),
  'location': Color(0xFF84CC16),
  'poll': Color(0xFF6366F1),
  'revoked': Color(0xFFF43F5E),
  'masked': Color(0xFF8B5CF6),
  'unknown': Color(0xFF64748B),
};
const _typeColorFallbacks = [
  Color(0xFF0EA5E9), Color(0xFFD946EF), Color(0xFFF97316),
  Color(0xFF10B981), Color(0xFF6366F1), Color(0xFFEAB308),
];
Color _colorForType(String name) {
  final mapped = _typeColors[name];
  if (mapped != null) return mapped;
  var hash = 0;
  for (final c in name.codeUnits) {
    hash = (hash * 31 + c) & 0x7fffffff;
  }
  return _typeColorFallbacks[hash % _typeColorFallbacks.length];
}

String _shortChatId(String chatId) => chatId.split('@').first;

/// Mirrors Dashboard.tsx's `formatLastActive` exactly (same thresholds and wording).
String _formatLastActive(String? iso) {
  if (iso == null || iso.isEmpty) return 'Never';
  final date = DateTime.tryParse(iso);
  if (date == null) return 'Never';
  final diff = DateTime.now().toUtc().difference(date.toUtc());
  if (diff.inMilliseconds < 60000) return 'Just now';
  if (diff.inMilliseconds < 3600000) return '${diff.inMinutes} min ago';
  if (diff.inMilliseconds < 86400000) return '${diff.inHours} hours ago';
  return '${date.day}/${date.month}/${date.year}';
}

class WaChatDashboardPage extends ConsumerStatefulWidget {
  const WaChatDashboardPage({super.key});
  @override
  ConsumerState<WaChatDashboardPage> createState() => _WaChatDashboardPageState();
}

class _WaChatDashboardPageState extends ConsumerState<WaChatDashboardPage> {
  List<Rec> _sessions = [];
  Rec _stats = {};
  Rec? _overview;
  int _webhookCount = 0;
  bool _loading = true;
  String? _error;
  bool _reconnecting = false;
  String? _apiKeyOverride;

  String _period = '24h';
  Rec? _messageStats;
  bool _statsLoading = false;
  bool _statsForbidden = false;
  String? _statsError;

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
      final sessions = await WaChatApiService.getSessions(key);
      final stats = await WaChatApiService.getSessionStats(key);
      List<Rec> webhooks = [];
      Rec? overview;
      try {
        webhooks = await WaChatApiService.getWebhooks(key);
      } catch (_) {}
      try {
        overview = await WaChatApiService.getStatsOverview(key);
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _sessions = sessions;
        _stats = stats;
        _webhookCount = webhooks.length;
        _overview = overview;
        _loading = false;
      });
      unawaited(_loadMessageStats());
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

  Future<void> _loadMessageStats() async {
    final key = _apiKey;
    if (key == null || key.isEmpty) return;
    setState(() { _statsLoading = true; _statsError = null; _statsForbidden = false; });
    try {
      final stats = await WaChatApiService.getMessageStats(key, _period);
      if (!mounted) return;
      setState(() { _messageStats = stats; _statsLoading = false; });
    } catch (e) {
      if (!mounted) return;
      // Non-admin keys 403 on /stats/messages for an unscoped key — but a session-scoped key (every
      // company's own token) reads its own sessions' aggregate fine, so a 403 here would mean a
      // future guard change; hide the section rather than showing a scary error, same as the React
      // dashboard's `forbidden` branch in DashboardCharts.tsx.
      final forbidden = e is DioException && e.response?.statusCode == 403;
      setState(() {
        _statsLoading = false;
        _statsForbidden = forbidden;
        _statsError = forbidden ? null : apiErrorMessage(e);
      });
    }
  }

  void _setPeriod(String p) {
    if (p == _period) return;
    setState(() => _period = p);
    _loadMessageStats();
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

  Future<void> _disconnectSession(Rec s) async {
    final key = _apiKey;
    final sessionId = str(s['id'], '');
    if (key == null || sessionId.isEmpty) return;
    if (!await confirm(context, title: 'Disconnect this session?', confirmLabel: 'Disconnect')) return;
    try {
      await WaChatApiService.stopSession(sessionId, key);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Disconnecting…')));
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final messagesToday = _overview != null
        ? (num.tryParse('${_overview!['messages']?['today']?['sent'] ?? 0}') ?? 0) +
            (num.tryParse('${_overview!['messages']?['today']?['received'] ?? 0}') ?? 0)
        : null;
    final totalMessages = _overview != null
        ? (num.tryParse('${_overview!['messages']?['sent'] ?? 0}') ?? 0) +
            (num.tryParse('${_overview!['messages']?['received'] ?? 0}') ?? 0)
        : null;
    final anyConnected = _sessions.any((s) => str(s['status'], '') == 'ready');

    return Scaffold(
      appBar: AppBar(title: const Text('WA Chat Dashboard')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? AppEmptyState(
                  icon: Icons.error_outline,
                  title: "Couldn't load the dashboard",
                  subtitle: _error,
                  action: TextButton(
                    onPressed: _reconnecting ? null : _reconnect,
                    child: _reconnecting
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Reconnect WA Chat'),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () async {
                    await _load();
                  },
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text('Overview of your WhatsApp sessions and activity',
                                style: TextStyle(color: context.mutedColor, fontSize: 13)),
                          ),
                          StatusPill(anyConnected ? 'Connected' : 'Disconnected'),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 15,
                        runSpacing: 10,
                        children: [
                          _statCard('Sessions List', '${_stats['ready'] ?? 0}',
                              '${_stats['active'] ?? 0} running · ${_stats['total'] ?? 0} total',
                              Icons.smartphone_rounded),
                          _statCard('Messages Today', messagesToday?.toStringAsFixed(0) ?? '—', null,
                              Icons.send_rounded),
                          _statCard('Webhooks Config.', '$_webhookCount', null, Icons.webhook_rounded),
                          _statCard('Total Messages', totalMessages?.toStringAsFixed(0) ?? '—', null,
                              Icons.bar_chart_rounded),
                        ],
                      ),
                      const SizedBox(height: 24),
                      _messageAnalytics(),
                      const SizedBox(height: 24),
                      Text('Sessions Overview',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                      Text('Showing ${_sessions.length} of ${_stats['total'] ?? _sessions.length} sessions',
                          style: TextStyle(fontSize: 12, color: context.mutedColor)),
                      const SizedBox(height: 10),
                      if (_sessions.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Center(child: Text('No sessions yet', style: TextStyle(color: context.mutedColor))),
                        )
                      else
                        ..._sessions.map((s) => _sessionRow(s)),
                    ],
                  ),
                ),
    );
  }

  Widget _statCard(String label, String value, String? detail, IconData icon) {
    return Container(
      width: 160,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.lineColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: TextStyle(fontSize: 12, color: context.mutedColor)),
              Icon(icon, size: 18, color: context.mutedColor),
            ],
          ),
          const SizedBox(height: 8),
          Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          if (detail != null) ...[
            const SizedBox(height: 2),
            Text(detail, style: TextStyle(fontSize: 11, color: context.mutedColor)),
          ],
        ],
      ),
    );
  }

  Widget _sessionRow(Rec s) {
    final status = str(s['status'], '');
    final canDisconnect = ['ready', 'initializing', 'qr_ready'].contains(status);
    final id = str(s['id'], '');
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.lineColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(id.length > 12 ? id.substring(0, 12) : id,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12, fontWeight: FontWeight.w600)),
              ),
              StatusPill(status.isEmpty ? 'unknown' : status),
            ],
          ),
          const SizedBox(height: 6),
          Text(str(s['name'], 'Session'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 2),
          Text('${str(s['phone'], 'No number')} · ${_formatLastActive(str(s['lastActive'] ?? s['connectedAt'], ''))}',
              style: TextStyle(fontSize: 12, color: context.mutedColor)),
          const SizedBox(height: 8),
          Row(
            children: [
              TextButton(
                onPressed: () => context.push('/wa-chat/sessions'),
                child: const Text('View'),
              ),
              if (canDisconnect)
                TextButton(
                  onPressed: () => _disconnectSession(s),
                  style: TextButton.styleFrom(foregroundColor: AppPalette.danger),
                  child: const Text('Disconnect'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Message Analytics ──────────────────────────────────────────────────
  // Mirrors DashboardCharts.tsx: a period toggle plus a messages-over-time area chart, a
  // by-type breakdown, and a top-chats ranking, all sourced from one /api/stats/messages call.

  Widget _messageAnalytics() {
    if (_statsForbidden) return const SizedBox.shrink();

    final timeSeries = (_messageStats?['timeSeries'] as List?)?.cast<Rec>() ?? const [];
    final byTypeRaw = (_messageStats?['byType'] as Map?)?.cast<String, dynamic>() ?? const {};
    final byType = byTypeRaw.entries.map((e) => (e.key, (num.tryParse('${e.value}') ?? 0).toInt())).toList()
      ..sort((a, b) => b.$2.compareTo(a.$2));
    final topChatsRaw = (_messageStats?['topChats'] as List?)?.cast<Rec>() ?? const [];
    final topChats = topChatsRaw.take(8).map((c) {
      final name = str(c['chatName'], '').isNotEmpty ? str(c['chatName']) : _shortChatId(str(c['chatId'], ''));
      return (name, (num.tryParse('${c['messageCount'] ?? 0}') ?? 0).toInt());
    }).toList();
    final hasData = timeSeries.isNotEmpty || byType.isNotEmpty || topChats.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(children: [
              const Icon(Icons.bar_chart_rounded, size: 18),
              const SizedBox(width: 8),
              Text('Message Analytics',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            ]),
            Wrap(
              spacing: 6,
              children: [
                for (final p in _dashboardPeriods)
                  ChoiceChip(label: Text(p), selected: _period == p, onSelected: (_) => _setPeriod(p)),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_statsLoading)
          const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Center(child: CircularProgressIndicator()))
        else if (_statsError != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(_statsError!, style: const TextStyle(color: AppPalette.danger)),
          )
        else if (!hasData)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(child: Text('No message activity in this period', style: TextStyle(color: context.mutedColor))),
          )
        else ...[
          if (timeSeries.isNotEmpty) _timeSeriesCard(timeSeries),
          const SizedBox(height: 12),
          if (byType.isNotEmpty) _byTypeCard(byType),
          const SizedBox(height: 12),
          if (topChats.isNotEmpty) _topChatsCard(topChats),
        ],
      ],
    );
  }

  Widget _chartCard(String title, Widget child) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.lineColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _timeSeriesCard(List<Rec> timeSeries) {
    String tick(String ts) => _period == '24h'
        ? (ts.length >= 16 ? ts.substring(11, 16) : ts)
        : (ts.length >= 10 ? ts.substring(5, 10) : ts);

    final sentSpots = <FlSpot>[];
    final receivedSpots = <FlSpot>[];
    for (var i = 0; i < timeSeries.length; i++) {
      final p = timeSeries[i];
      sentSpots.add(FlSpot(i.toDouble(), (num.tryParse('${p['sent'] ?? 0}') ?? 0).toDouble()));
      receivedSpots.add(FlSpot(i.toDouble(), (num.tryParse('${p['received'] ?? 0}') ?? 0).toDouble()));
    }
    final step = (timeSeries.length / 5).ceil().clamp(1, timeSeries.length);

    return _chartCard(
      'Messages over time',
      Column(
        children: [
          SizedBox(
            height: 220,
            child: LineChart(LineChartData(
              gridData: const FlGridData(show: true, drawVerticalLine: false),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 32,
                    getTitlesWidget: (v, meta) => Text(v.toInt().toString(),
                        style: TextStyle(fontSize: 10, color: context.mutedColor)))),
                bottomTitles: AxisTitles(sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 24,
                  interval: step.toDouble(),
                  getTitlesWidget: (v, meta) {
                    final i = v.toInt();
                    if (i < 0 || i >= timeSeries.length) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(tick(str(timeSeries[i]['timestamp'], '')),
                          style: TextStyle(fontSize: 10, color: context.mutedColor)),
                    );
                  },
                )),
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: sentSpots, isCurved: true, color: AppPalette.success, barWidth: 2,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(show: true, color: AppPalette.success.withValues(alpha: 0.15)),
                ),
                LineChartBarData(
                  spots: receivedSpots, isCurved: true, color: const Color(0xFF3B82F6), barWidth: 2,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(show: true, color: const Color(0xFF3B82F6).withValues(alpha: 0.15)),
                ),
              ],
            )),
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 16, children: [
            _legendDot(AppPalette.success, 'Sent'),
            _legendDot(const Color(0xFF3B82F6), 'Received'),
          ]),
        ],
      ),
    );
  }

  Widget _byTypeCard(List<(String, int)> byType) {
    final total = byType.fold<int>(0, (a, b) => a + b.$2);
    return _chartCard(
      'Messages by type',
      Column(
        children: [
          SizedBox(
            height: 180,
            child: PieChart(PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 40,
              sections: byType.map((e) {
                final pct = total == 0 ? 0.0 : e.$2 / total * 100;
                return PieChartSectionData(
                  value: e.$2.toDouble(),
                  color: _colorForType(e.$1),
                  radius: 46,
                  title: pct >= 8 ? '${pct.toStringAsFixed(0)}%' : '',
                  titleStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white),
                );
              }).toList(),
            )),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: byType.map((e) => _legendDot(_colorForType(e.$1), '${e.$1} (${e.$2})')).toList(),
          ),
        ],
      ),
    );
  }

  Widget _topChatsCard(List<(String, int)> topChats) {
    final maxCount = topChats.fold<int>(1, (m, c) => c.$2 > m ? c.$2 : m);
    return _chartCard(
      'Top chats',
      Column(
        children: topChats.map((c) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                SizedBox(
                  width: 96,
                  child: Text(c.$1, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: c.$2 / maxCount,
                      minHeight: 14,
                      backgroundColor: context.lineColor,
                      valueColor: const AlwaysStoppedAnimation(AppPalette.success),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text('${c.$2}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 6),
      Text(label, style: TextStyle(fontSize: 11, color: context.mutedColor)),
    ]);
  }
}

