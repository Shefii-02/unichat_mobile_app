// WA Chat's "Api Service" quick link — mirrors frontend/src/pages/wa-chat/pages/WaOtpService.tsx.
// 8 tabs: the 3 config-kind CRUD tabs (Auth OTP API / Utility / Invoice Share, in
// otp_config_editor_page.dart) plus Test Send / API Docs / Settings / Logs / Export History,
// all Laravel-proxied under /otp-service/* — no gateway/wa_chat_token calls anywhere here.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:unichat_mobile_app/core/constants/api_constants.dart';
import 'package:unichat_mobile_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:unichat_mobile_app/features/modules/_shared.dart';
import 'package:unichat_mobile_app/features/operations/presentation/pages/otp_config_editor_page.dart';

class OtpServicePage extends ConsumerStatefulWidget {
  const OtpServicePage({super.key});
  @override
  ConsumerState<OtpServicePage> createState() => _OtpServicePageState();
}

class _OtpServicePageState extends ConsumerState<OtpServicePage> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 8, vsync: this);

  Rec? _service;
  bool _loadingService = true;
  final _domainsCtrl = TextEditingController();
  final _packagesCtrl = TextEditingController();
  bool _savingSettings = false;
  bool _settingsSaved = false;

  List<Rec> _sessions = [];

  List<Rec> _logs = [];
  bool _loadingLogs = false;
  bool _exporting = false;
  DateTime? _logsFrom;
  DateTime? _logsTo;
  String? _logsSessionId;

  String _testType = 'otp'; // otp | utility | invoice
  final _testPhoneCtrl = TextEditingController();
  String? _testServiceName;
  final _testMessageCtrl = TextEditingController();
  final _testFileUrlCtrl = TextEditingController();
  final Map<String, TextEditingController> _testVarCtrls = {};
  List<Rec>? _testConfigs;
  bool _testLoading = false;
  Rec? _testResult;

  String get _testKind => _testType == 'otp' ? 'auth' : _testType;

  static const _authAutoTokens = {'otp', 'code', 'expiry'};
  static const _utilAutoTokens = {'company', 'company_name', 'business name'};

  @override
  void initState() {
    super.initState();
    _loadService();
    _loadSessions();
    _loadTestConfigs();
    _loadLogs();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _domainsCtrl.dispose();
    _packagesCtrl.dispose();
    _testPhoneCtrl.dispose();
    _testMessageCtrl.dispose();
    _testFileUrlCtrl.dispose();
    for (final c in _testVarCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadService() async {
    setState(() => _loadingService = true);
    try {
      final raw = await Api.one('/otp-service');
      final service = raw['id'] != null ? raw : null;
      if (mounted) {
        setState(() {
          _service = service;
          _domainsCtrl.text = ((_service?['allowed_domains'] as List?) ?? []).join('\n');
          _packagesCtrl.text = ((_service?['allowed_packages'] as List?) ?? []).join('\n');
          _loadingService = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loadingService = false);
    }
  }

  Future<void> _loadSessions() async {
    try {
      final sessions = await Api.list('/otp-service/sessions');
      if (mounted) setState(() => _sessions = sessions);
    } catch (_) {}
  }

  Future<void> _loadTestConfigs() async {
    setState(() => _testConfigs = null);
    try {
      final configs = await Api.list('/otp-service/configs', query: {'kind': _testKind});
      if (mounted) setState(() => _testConfigs = configs);
    } catch (_) {
      if (mounted) setState(() => _testConfigs = []);
    }
  }

  Future<void> _loadLogs() async {
    setState(() => _loadingLogs = true);
    try {
      final query = <String, dynamic>{'per_page': 200};
      if (_logsFrom != null) query['from'] = _logsFrom!.toIso8601String().substring(0, 10);
      if (_logsTo != null) query['to'] = _logsTo!.toIso8601String().substring(0, 10);
      if (_logsSessionId != null) query['session_id'] = _logsSessionId;
      final logs = await Api.list('/otp-service/logs', query: query);
      if (mounted) setState(() { _logs = logs; _loadingLogs = false; });
    } catch (e) {
      if (mounted) setState(() => _loadingLogs = false);
    }
  }

  Future<void> _exportLogs() async {
    if (_logs.isEmpty) return;
    setState(() => _exporting = true);
    try {
      final rows = <String>['#,Phone,Action,Session,IP,Domain,Response(ms),Time'];
      for (var i = 0; i < _logs.length; i++) {
        final l = _logs[i];
        rows.add(
          '${i + 1},"${str(l['phone'])}","${str(l['action'])}","${str(l['session_id'], '')}","${str(l['ip_address'], '')}","${str(l['domain'], '')}",${l['response_ms'] ?? ''},"${when(str(l['created_at'], ''))}"',
        );
      }
      final csv = rows.join('\n');
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/api-service-logs-${DateTime.now().millisecondsSinceEpoch}.csv');
      await file.writeAsString(csv);
      if (mounted) await Share.shareXFiles([XFile(file.path)], text: 'API Service logs export');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _saveSettings() async {
    setState(() { _savingSettings = true; _settingsSaved = false; });
    try {
      await Api.post('/otp-service', data: {
        'allowed_domains': _domainsCtrl.text.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toList(),
        'allowed_packages': _packagesCtrl.text.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toList(),
      });
      if (mounted) {
        setState(() { _savingSettings = false; _settingsSaved = true; });
        _loadService();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _savingSettings = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
      }
    }
  }

  Future<void> _resetToken() async {
    if (!await confirm(
      context,
      title: 'Regenerate API Token?',
      message: 'This will immediately invalidate the current API token. All apps using the old token will stop working until updated.',
      destructive: true,
      confirmLabel: 'Yes, Regenerate',
    )) {
      return;
    }
    try {
      final res = await Api.post('/otp-service/reset-token');
      final service = res['data'] as Map?;
      final token = service?['api_token'] as String?;
      await _loadService();
      if (mounted && token != null) _showNewTokenDialog(token);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
    }
  }

  Future<void> _stopToken() async {
    final ok = await runAction(context, () => Api.post('/otp-service/stop-token'), success: 'Token revoked');
    if (ok) _loadService();
  }

  void _showNewTokenDialog(String token) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New API Token Generated'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Copy this token now — it will not be shown again in full.', style: TextStyle(color: AppPalette.danger, fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(8)),
              child: SelectableText(token, style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 12)),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Clipboard.setData(ClipboardData(text: token)), child: const Text('Copy')),
          FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text("I've copied it")),
        ],
      ),
    );
  }

  Rec? get _selectedTestConfig {
    final configs = _testConfigs ?? [];
    final matches = configs.where((c) => c['name'] == _testServiceName);
    return matches.isEmpty ? null : matches.first;
  }

  String get _templateSource {
    if (_testType == 'invoice') return '';
    if (_testMessageCtrl.text.trim().isNotEmpty) return _testMessageCtrl.text.trim();
    final cfg = _selectedTestConfig;
    final tplContent = (cfg?['prebuilt_template'] as Map?)?['content'] as String?;
    return tplContent ?? str(cfg?['custom_content'], '');
  }

  List<String> get _testVarNames {
    final auto = _testType == 'otp' ? _authAutoTokens : _utilAutoTokens;
    final set = <String>{};
    for (final m in RegExp(r'\{\{\s*(.+?)\s*\}\}').allMatches(_templateSource)) {
      final name = m.group(1)!.trim();
      if (!auto.contains(name.toLowerCase())) set.add(name);
    }
    return set.toList();
  }

  Future<void> _runTestSend() async {
    if (_testPhoneCtrl.text.trim().isEmpty) return;
    setState(() { _testLoading = true; _testResult = null; });
    try {
      final service = (_testServiceName?.trim().isNotEmpty ?? false) ? _testServiceName!.trim() : null;
      final varNames = _testVarNames;
      final variables = varNames.isEmpty ? null : {for (final n in varNames) n: _testVarCtrls[n]?.text ?? ''};
      Rec res;
      if (_testType == 'otp') {
        res = await Api.post('/otp-service/test-send', data: {
          'phone': _testPhoneCtrl.text.trim(),
          if (service != null) 'service': service,
          if (variables != null) 'variables': variables,
        });
      } else if (_testType == 'utility') {
        res = await Api.post('/otp-service/utility-send', data: {
          'phone': _testPhoneCtrl.text.trim(),
          if (service != null) 'service': service,
          if (_testMessageCtrl.text.trim().isNotEmpty) 'message': _testMessageCtrl.text.trim(),
          if (variables != null) 'variables': variables,
        });
      } else {
        res = await Api.post('/otp-service/invoice-share', data: {
          'phone': _testPhoneCtrl.text.trim(),
          if (service != null) 'service': service,
          if (_testFileUrlCtrl.text.trim().isNotEmpty) 'file_url': _testFileUrlCtrl.text.trim(),
          'filename': 'test-invoice.pdf',
          'caption': 'Test invoice share',
        });
      }
      if (mounted) setState(() { _testResult = {...res, 'success': true}; _testLoading = false; });
    } catch (e) {
      if (mounted) setState(() { _testResult = {'success': false, 'error': apiErrorMessage(e)}; _testLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Api Service'),
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabs: const [
            Tab(text: 'Auth OTP API'),
            Tab(text: 'Utility'),
            Tab(text: 'Invoice Share'),
            Tab(text: 'Test Send'),
            Tab(text: 'API Docs'),
            Tab(text: 'Settings'),
            Tab(text: 'Logs'),
            Tab(text: 'Export History'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          const ApiConfigListTab(kind: 'auth'),
          const ApiConfigListTab(kind: 'utility'),
          const ApiConfigListTab(kind: 'invoice'),
          _testSendTab(),
          _apiDocsTab(),
          _settingsTab(),
          _logsTab(),
          _exportHistoryTab(),
        ],
      ),
    );
  }

  // ---- Test Send ----

  Widget _testSendTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(spacing: 8, children: [
          _typeChip('otp', '🔐 Auth OTP'),
          _typeChip('utility', '💬 Utility'),
          _typeChip('invoice', '📄 Invoice'),
        ]),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(border: Border.all(color: context.lineColor), borderRadius: BorderRadius.circular(12)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Test ${_testType == 'otp' ? 'Auth OTP Send' : _testType == 'utility' ? 'Utility Message' : 'Invoice Share'}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                _testType == 'otp'
                    ? 'Sends a real OTP using the selected config (or the first active one).'
                    : _testType == 'utility'
                        ? 'Sends a utility message from the selected config, or the message typed below.'
                        : 'Shares a document from the selected config, or the File URL below.',
                style: TextStyle(fontSize: 12, color: context.mutedColor),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _testPhoneCtrl,
                keyboardType: TextInputType.phone,
                onChanged: (_) => setState(() => _testResult = null),
                decoration: const InputDecoration(labelText: 'Phone Number', hintText: 'e.g. 919876543210'),
              ),
              const SizedBox(height: 12),
              if ((_testConfigs ?? []).isNotEmpty)
                DropdownButtonFormField<String>(
                  initialValue: _testServiceName,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Config'),
                  items: [
                    const DropdownMenuItem<String>(value: null, child: Text('First active config')),
                    ...(_testConfigs ?? []).map((c) => DropdownMenuItem(
                          value: str(c['name']),
                          child: Text('${str(c['name'])}${c['is_active'] == false ? ' (inactive)' : ''}'),
                        )),
                  ],
                  onChanged: (v) => setState(() { _testServiceName = v; _testVarCtrls.clear(); _testResult = null; }),
                )
              else if (_testConfigs != null)
                Text(
                  'No $_testKind configs yet — create one on the ${_testKind == 'auth' ? 'Auth OTP API' : _testKind == 'utility' ? 'Utility' : 'Invoice Share'} tab.',
                  style: const TextStyle(fontSize: 12, color: AppPalette.warning),
                ),
              if (_testType == 'utility') ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _testMessageCtrl,
                  maxLines: 3,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(labelText: 'Message (overrides the config)', hintText: "Leave blank to use the config's content…"),
                ),
              ],
              if (_testType != 'invoice' && _testVarNames.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'Template variables (fill each {{…}}${_testType == 'otp' ? '; the OTP code is auto-filled' : ''})',
                  style: TextStyle(fontSize: 12, color: context.mutedColor),
                ),
                const SizedBox(height: 6),
                for (final name in _testVarNames)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: context.altSurface, borderRadius: BorderRadius.circular(4)),
                        child: Text('{{$name}}', style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _testVarCtrls.putIfAbsent(name, () => TextEditingController()),
                          decoration: InputDecoration(hintText: 'value for $name', isDense: true),
                        ),
                      ),
                    ]),
                  ),
              ],
              if (_testType == 'invoice') ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _testFileUrlCtrl,
                  decoration: const InputDecoration(labelText: 'File URL (overrides the config)', hintText: 'https://example.com/invoice.pdf'),
                ),
              ],
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: (_testLoading || _testPhoneCtrl.text.trim().isEmpty) ? null : _runTestSend,
                icon: _testLoading
                    ? const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.send_rounded, size: 15),
                label: Text(_testLoading ? 'Sending…' : 'Send Test'),
              ),
              if (_testResult != null) _testResultCard(_testResult!),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: context.altSurface, borderRadius: BorderRadius.circular(10)),
          child: const Text('Note: This sends a real WhatsApp message. Test charges may apply depending on your plan.', style: TextStyle(fontSize: 12)),
        ),
      ],
    );
  }

  Widget _typeChip(String value, String label) => ChoiceChip(
        label: Text(label),
        selected: _testType == value,
        onSelected: (_) {
          setState(() { _testType = value; _testServiceName = null; _testVarCtrls.clear(); _testResult = null; });
          _loadTestConfigs();
        },
      );

  Widget _testResultCard(Rec r) {
    final success = r['success'] == true;
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: success ? AppPalette.success.withValues(alpha: 0.08) : AppPalette.danger.withValues(alpha: 0.08),
        border: Border.all(color: (success ? AppPalette.success : AppPalette.danger).withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: success
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(children: [
                  Icon(Icons.check_circle_rounded, color: AppPalette.success, size: 18),
                  SizedBox(width: 6),
                  Text('Success!', style: TextStyle(fontWeight: FontWeight.w700, color: AppPalette.success)),
                ]),
                if (r['otp'] != null)
                  Padding(padding: const EdgeInsets.only(top: 8), child: Text('OTP: ${r['otp']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, letterSpacing: 3))),
                if (r['message'] != null)
                  Padding(padding: const EdgeInsets.only(top: 4), child: Text('${r['message']}', style: const TextStyle(fontStyle: FontStyle.italic, fontSize: 13))),
                if (r['ms'] != null)
                  Padding(padding: const EdgeInsets.only(top: 4), child: Text('${r['ms']}ms', style: TextStyle(fontSize: 11, color: context.mutedColor))),
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.cancel_rounded, color: AppPalette.danger, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Failed', style: TextStyle(fontWeight: FontWeight.w700, color: AppPalette.danger)),
                      Text(str(r['error'], 'Send failed'), style: const TextStyle(fontSize: 13)),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  // ---- API Docs ----

  Widget _apiDocsTab() {
    final user = ref.read(authProvider).value;
    final waChatToken = user?.waContactToken ?? '{wa-chat-token}';
    final baseUrl = '${ApiConstants.laravelOrigin}/api/v1/$waChatToken';
    final token = str(_service?['api_token'], '<your-api-token>');
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(children: [
          const Icon(Icons.menu_book_rounded, color: AppPalette.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Api Service — Integration Guide', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                Text('Use your Bearer token to integrate OTP, Utility Messages, and Invoice Share into any platform.', style: TextStyle(fontSize: 12, color: context.mutedColor)),
              ],
            ),
          ),
        ]),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: AppPalette.info.withValues(alpha: 0.08), border: Border.all(color: AppPalette.info.withValues(alpha: 0.3)), borderRadius: BorderRadius.circular(10)),
          child: Column(children: [
            _copyRow('Base URL', baseUrl),
            const SizedBox(height: 8),
            _copyRow('API token', token),
          ]),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: AppPalette.warning.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
          child: const Text(
            'Authentication: the {wa-chat-token} in the URL path identifies your company; every request also needs the Authorization: Bearer <token> header. Optionally restrict by domain (Origin header) or app package (X-App-Package header).',
            style: TextStyle(fontSize: 12),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: AppPalette.info.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
          child: const Text(
            'Choosing a config: pass "service": "<config name>" in the body to select one of your named configs. Omit it to use the first active config of that type.',
            style: TextStyle(fontSize: 12),
          ),
        ),
        const SizedBox(height: 20),
        _endpointDoc(
          'POST',
          '/otp/send',
          'Send a WhatsApp OTP to a phone number. Returns expires_at for countdown display.',
          'curl -X POST $baseUrl/otp/send \\\n  -H "Authorization: Bearer $token" \\\n  -H "Content-Type: application/json" \\\n  -d \'{"phone": "919876543210", "service": "login"}\'',
        ),
        _endpointDoc(
          'POST',
          '/otp/verify',
          'Verify an OTP entered by the user.',
          'curl -X POST $baseUrl/otp/verify \\\n  -H "Authorization: Bearer $token" \\\n  -H "Content-Type: application/json" \\\n  -d \'{"phone": "919876543210", "otp": "123456"}\'',
        ),
        _endpointDoc(
          'POST',
          '/api-service/utility-send',
          'Send a utility message — either your own message, or a configured service.',
          'curl -X POST $baseUrl/api-service/utility-send \\\n  -H "Authorization: Bearer $token" \\\n  -H "Content-Type: application/json" \\\n  -d \'{"phone": "919876543210", "service": "order-shipped"}\'',
        ),
        _endpointDoc(
          'POST',
          '/api-service/invoice-share',
          'Share a document (invoice, receipt, contract) via public URL.',
          'curl -X POST $baseUrl/api-service/invoice-share \\\n  -H "Authorization: Bearer $token" \\\n  -H "Content-Type: application/json" \\\n  -d \'{"phone": "919876543210", "file_url": "https://yourdomain.com/invoice.pdf"}\'',
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(border: Border.all(color: context.lineColor), borderRadius: BorderRadius.circular(10)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Error Codes', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              for (final e in const [
                ('401', 'Invalid or missing Bearer token'),
                ('403', 'Origin or app package not in allowed list'),
                ('422', 'Validation error or no WA session configured'),
                ('500', 'WAHA delivery failure or server error'),
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: AppPalette.danger.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                      child: Text(e.$1, style: const TextStyle(fontSize: 11, color: AppPalette.danger, fontFamily: 'monospace')),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(e.$2, style: TextStyle(fontSize: 12, color: context.mutedColor))),
                  ]),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _copyRow(String label, String value) => Row(children: [
        Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
        const SizedBox(width: 8),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 11, fontFamily: 'monospace'), overflow: TextOverflow.ellipsis)),
        IconButton(
          icon: const Icon(Icons.copy_rounded, size: 16),
          constraints: const BoxConstraints(),
          padding: const EdgeInsets.all(4),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: value));
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied')));
          },
        ),
      ]);

  Widget _endpointDoc(String method, String path, String description, String curl) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: AppPalette.success.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
              child: Text(method, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppPalette.success)),
            ),
            Text('/api/v1/{wa-chat-token}$path', style: const TextStyle(fontSize: 13, fontFamily: 'monospace')),
          ]),
          const SizedBox(height: 6),
          Text(description, style: TextStyle(fontSize: 12, color: context.mutedColor)),
          const SizedBox(height: 8),
          _codeBlock(curl),
        ],
      ),
    );
  }

  Widget _codeBlock(String code) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: code));
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied')));
              },
              style: TextButton.styleFrom(minimumSize: Size.zero, padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2)),
              child: const Text('Copy', style: TextStyle(color: Colors.white70, fontSize: 11)),
            ),
          ),
          SelectableText(code, style: const TextStyle(color: Color(0xFFE2E8F0), fontSize: 11.5, fontFamily: 'monospace', height: 1.5)),
        ],
      ),
    );
  }

  // ---- Settings ----

  Widget _settingsTab() {
    if (_loadingService) return const Center(child: CircularProgressIndicator());
    final token = _service?['api_token'] as String?;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(border: Border.all(color: context.lineColor), borderRadius: BorderRadius.circular(10)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('API Token', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              const SizedBox(height: 4),
              Text('One Bearer token for all public endpoints. Sends via your WhatsApp Chat session.', style: TextStyle(fontSize: 11, color: context.mutedColor)),
              const SizedBox(height: 12),
              if (token != null) ...[
                SelectableText(token, style: const TextStyle(fontFamily: 'monospace', fontSize: 12, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                if (_service?['api_token_created_at'] != null)
                  Text('Updated: ${when(str(_service?['api_token_created_at']))}', style: TextStyle(fontSize: 11, color: context.mutedColor)),
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  OutlinedButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: token));
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied')));
                    },
                    icon: const Icon(Icons.copy_rounded, size: 14),
                    label: const Text('Copy'),
                  ),
                  OutlinedButton.icon(onPressed: _resetToken, icon: const Icon(Icons.refresh_rounded, size: 14), label: const Text('Regenerate')),
                  OutlinedButton.icon(
                    onPressed: _stopToken,
                    style: OutlinedButton.styleFrom(foregroundColor: AppPalette.danger, side: const BorderSide(color: AppPalette.danger)),
                    icon: const Icon(Icons.block_rounded, size: 14),
                    label: const Text('Revoke'),
                  ),
                ]),
              ] else
                FilledButton.icon(onPressed: _resetToken, icon: const Icon(Icons.shield_rounded, size: 16), label: const Text('Generate API Token')),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: AppPalette.info.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
          child: const Text(
            'OTP length, expiry, attempt limits, the message template and the WhatsApp session are set per config on the Auth OTP API / Utility / Invoice Share tabs.',
            style: TextStyle(fontSize: 12),
          ),
        ),
        const SizedBox(height: 16),
        TextField(controller: _domainsCtrl, maxLines: 3, decoration: const InputDecoration(labelText: 'Allowed Websites / Domains (one per line)', hintText: 'https://yourapp.com')),
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 16),
          child: Text('Leave blank to allow all origins. Checked against the Origin HTTP header.', style: TextStyle(fontSize: 11, color: context.mutedColor)),
        ),
        TextField(controller: _packagesCtrl, maxLines: 2, decoration: const InputDecoration(labelText: 'Allowed App Packages (one per line)', hintText: 'com.yourcompany.app')),
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 16),
          child: Text('Checked against X-App-Package HTTP header. Leave blank to allow all packages.', style: TextStyle(fontSize: 11, color: context.mutedColor)),
        ),
        FilledButton(
          onPressed: _savingSettings ? null : _saveSettings,
          child: _savingSettings
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Save Settings'),
        ),
        if (_settingsSaved) const Padding(padding: EdgeInsets.only(top: 8), child: Text('Settings saved.', style: TextStyle(color: AppPalette.success, fontSize: 13))),
      ],
    );
  }

  // ---- Logs / Export History ----

  Widget _logsFilterBar() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Expanded(child: _dateField('From', _logsFrom, (d) { setState(() => _logsFrom = d); _loadLogs(); })),
          const SizedBox(width: 8),
          Expanded(child: _dateField('To', _logsTo, (d) { setState(() => _logsTo = d); _loadLogs(); })),
        ]),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: _logsSessionId,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Session', isDense: true),
          items: [
            const DropdownMenuItem<String>(value: null, child: Text('All sessions')),
            ..._sessions.map((s) => DropdownMenuItem(
                  value: str(s['id']),
                  child: Text('${str(s['display_name'] ?? s['id'])}${s['connected'] == true ? '' : ' (offline)'}', overflow: TextOverflow.ellipsis),
                )),
          ],
          onChanged: (v) { setState(() => _logsSessionId = v); _loadLogs(); },
        ),
        if (_logsFrom != null || _logsTo != null || _logsSessionId != null)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () { setState(() { _logsFrom = null; _logsTo = null; _logsSessionId = null; }); _loadLogs(); },
              child: const Text('Clear'),
            ),
          ),
      ],
    );
  }

  Widget _dateField(String label, DateTime? value, ValueChanged<DateTime?> onChanged) {
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(context: context, initialDate: value ?? DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime.now().add(const Duration(days: 1)));
        onChanged(picked);
      },
      child: InputDecorator(
        decoration: InputDecoration(labelText: label, isDense: true),
        child: Text(value == null ? '—' : '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}'),
      ),
    );
  }

  Widget _logsTab() {
    return Column(children: [
      Padding(padding: const EdgeInsets.all(16), child: _logsFilterBar()),
      Expanded(
        child: _loadingLogs
            ? const Center(child: CircularProgressIndicator())
            : _logs.isEmpty
                ? Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.receipt_long_rounded, size: 36, color: context.mutedColor.withValues(alpha: 0.4)),
                      const SizedBox(height: 8),
                      Text('No logs yet.', style: TextStyle(color: context.mutedColor)),
                    ]),
                  )
                : RefreshIndicator(
                    onRefresh: _loadLogs,
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      itemCount: _logs.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) => _logTile(_logs[i]),
                    ),
                  ),
      ),
    ]);
  }

  Widget _logTile(Rec l) {
    final action = str(l['action'], '');
    final color = switch (action) {
      'verified' => AppPalette.success,
      'failed' => AppPalette.danger,
      'invoice_share' => AppPalette.info,
      'utility' => AppPalette.accent,
      _ => AppPalette.muted,
    };
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(str(l['phone']), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      subtitle: Text(
        '${str(l['session_id'], '—')} · ${str(l['ip_address'], '')} · ${l['response_ms'] ?? '—'}ms · ${when(str(l['created_at'], ''))}',
        style: TextStyle(fontSize: 11, color: context.mutedColor),
      ),
      trailing: StatusPill(action, color: color),
    );
  }

  Map<String, int> get _actionCounts {
    final counts = <String, int>{};
    for (final l in _logs) {
      final a = str(l['action'], '');
      counts[a] = (counts[a] ?? 0) + 1;
    }
    return counts;
  }

  Widget _exportHistoryTab() {
    final filtered = _logsFrom != null || _logsTo != null || _logsSessionId != null;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(border: Border.all(color: context.lineColor), borderRadius: BorderRadius.circular(12)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(children: [Icon(Icons.download_rounded, size: 18), SizedBox(width: 8), Text('Export Api Service Logs', style: TextStyle(fontWeight: FontWeight.w700))]),
            const SizedBox(height: 6),
            Text('Download a CSV of OTP, utility and invoice-share activity. Narrow by date range and session first.', style: TextStyle(fontSize: 12, color: context.mutedColor)),
            const SizedBox(height: 14),
            _logsFilterBar(),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: (_exporting || _logs.isEmpty) ? null : _exportLogs,
              icon: _exporting
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.download_rounded, size: 16),
              label: Text('Download ${filtered ? 'Filtered' : 'All'} Logs (.csv)'),
            ),
            if (_logs.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 12), child: Text('${_logs.length} log entries available.', style: TextStyle(fontSize: 12, color: context.mutedColor))),
          ],
        ),
      ),
      if (_logs.isNotEmpty) ...[
        const SizedBox(height: 20),
        const Text('Action Summary', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        Wrap(spacing: 10, runSpacing: 10, children: [
          for (final e in _actionCounts.entries)
            Container(
              width: 110,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(border: Border.all(color: context.lineColor), borderRadius: BorderRadius.circular(10)),
              child: Column(children: [
                Text('${e.value}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppPalette.accent)),
                const SizedBox(height: 2),
                Text(e.key, style: const TextStyle(fontSize: 11)),
              ]),
            ),
        ]),
      ],
    ]);
  }
}
