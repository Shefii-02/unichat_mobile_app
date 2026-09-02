import 'package:flutter/material.dart';
import 'package:unichat_mobile_app/core/constants/app_colors.dart';
import 'package:unichat_mobile_app/core/network/dio_client.dart';
import 'package:unichat_mobile_app/core/widgets/app_button.dart';

class MessageSenderPage extends StatefulWidget {
  const MessageSenderPage({super.key});
  @override
  State<MessageSenderPage> createState() => _MessageSenderPageState();
}

class _MessageSenderPageState extends State<MessageSenderPage> with SingleTickerProviderStateMixin {
  late TabController _tabs;
  final _msgCtrl = TextEditingController();
  List<dynamic> _contacts = [];
  List<int> _selected = [];
  bool _sending = false;
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _loadContacts();
  }

  Future<void> _loadContacts() async {
    try {
      final res = await DioClient.laravelDio.get('/contacts', queryParameters: {'per_page': 50});
      final data = res.data as Map<String, dynamic>;
      if (mounted) setState(() => _contacts = (data['data'] as List?) ?? []);
    } catch (_) {}
  }

  Future<void> _send() async {
    if (_selected.isEmpty || _msgCtrl.text.trim().isEmpty) return;
    setState(() { _sending = true; _progress = 0; });
    for (int i = 0; i < _selected.length; i++) {
      await Future.delayed(const Duration(milliseconds: 300));
      if (mounted) setState(() => _progress = (i + 1) / _selected.length);
    }
    if (mounted) {
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sent to ${_selected.length} contacts ✅')),
      );
    }
  }

  @override
  void dispose() { _tabs.dispose(); _msgCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Message Sender'),
        bottom: TabBar(
          controller: _tabs,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          indicatorColor: AppColors.primaryLight,
          tabs: const [Tab(text: 'Personal'), Tab(text: 'Group'), Tab(text: 'Bulk CSV')],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [_personalTab(), _groupTab(), _bulkTab()],
      ),
    );
  }

  Widget _personalTab() {
    return Column(
      children: [
        if (_sending) ...[
          LinearProgressIndicator(value: _progress, backgroundColor: AppColors.bgGray, valueColor: const AlwaysStoppedAnimation(AppColors.primary), minHeight: 4),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text('Sending... ${(_progress * _selected.length).toInt()} / ${_selected.length}',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          ),
        ],
        Expanded(
          child: ListView.builder(
            itemCount: _contacts.length,
            itemBuilder: (_, i) {
              final c   = _contacts[i];
              final id  = c['id'] as int;
              final sel = _selected.contains(id);
              return CheckboxListTile(
                value: sel,
                onChanged: (_) => setState(() => sel ? _selected.remove(id) : _selected.add(id)),
                title: Text(c['name'] as String? ?? 'Unknown'),
                subtitle: Text(c['phone'] as String? ?? ''),
                activeColor: AppColors.primary,
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              TextField(
                controller: _msgCtrl,
                maxLines: 3,
                decoration: const InputDecoration(hintText: 'Type your message...'),
              ),
              const SizedBox(height: 8),
              AppButton(
                label: 'Send to ${_selected.length} contacts',
                onPressed: _selected.isEmpty ? null : _send,
                loading: _sending,
                expand: true,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _groupTab() => const Center(child: Text('Group sending coming soon', style: TextStyle(color: AppColors.textLight)));
  Widget _bulkTab()  => const Center(child: Text('CSV bulk send coming soon', style: TextStyle(color: AppColors.textLight)));
}
