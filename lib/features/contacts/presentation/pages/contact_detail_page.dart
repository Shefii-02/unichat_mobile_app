import 'package:flutter/material.dart';
import 'package:unichat_mobile_app/core/constants/app_colors.dart';
import 'package:unichat_mobile_app/core/network/dio_client.dart';
import 'package:unichat_mobile_app/core/utils/format_utils.dart';
import 'package:unichat_mobile_app/core/widgets/app_avatar.dart';
import 'package:url_launcher/url_launcher.dart';

class ContactDetailPage extends StatefulWidget {
  const ContactDetailPage({super.key, required this.id});
  final int id;
  @override
  State<ContactDetailPage> createState() => _ContactDetailPageState();
}

class _ContactDetailPageState extends State<ContactDetailPage> with SingleTickerProviderStateMixin {
  late TabController _tabs;
  Map<String, dynamic>? _contact;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await DioClient.laravelDio.get('/contacts/${widget.id}');
      final data = res.data as Map<String, dynamic>;
      setState(() { _contact = data['contact'] as Map<String, dynamic>? ?? data; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() { _tabs.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final name = _contact?['name'] as String? ?? 'Contact';
    return Scaffold(
      appBar: AppBar(
        title: Text(name),
        bottom: TabBar(
          controller: _tabs,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          indicatorColor: AppColors.primaryLight,
          tabs: const [Tab(text: 'Info'), Tab(text: 'Leads'), Tab(text: 'Chats'), Tab(text: 'Timeline')],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _contact == null
              ? const Center(child: Text('Contact not found'))
              : TabBarView(
                  controller: _tabs,
                  children: [_info(), _leads(), _chats(), _timeline()],
                ),
    );
  }

  Widget _info() {
    final name  = _contact?['name'] as String? ?? '';
    final phone = _contact?['phone'] as String? ?? '';
    final email = _contact?['email'] as String? ?? '';
    final opted = _contact?['opted_in'] as bool? ?? false;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          AppAvatar(name: name, size: 80),
          const SizedBox(height: 12),
          Text(name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          Text(FormatUtils.phone(phone), style: const TextStyle(color: AppColors.textSecondary)),
          if (email.isNotEmpty) Text(email, style: const TextStyle(color: AppColors.textLight)),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: opted ? AppColors.success.withAlpha(20) : AppColors.error.withAlpha(20),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(opted ? '✅ Opted In' : '🚫 Opted Out',
                style: TextStyle(color: opted ? AppColors.success : AppColors.error, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _actionBtn('💬 Message', () {}),
              _actionBtn('📞 WA Call', () => launchUrl(Uri.parse('https://wa.me/${phone.replaceAll(RegExp(r'[^0-9]'), '')}'))),
              _actionBtn('➕ Lead', () {}),
            ],
          ),
        ],
      ),
    );
  }

  Widget _actionBtn(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(20)),
        child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
      ),
    );
  }

  Widget _leads()    => const Center(child: Text('Leads history coming soon', style: TextStyle(color: AppColors.textLight)));
  Widget _chats()    => const Center(child: Text('Chat history coming soon', style: TextStyle(color: AppColors.textLight)));
  Widget _timeline() => const Center(child: Text('Timeline coming soon', style: TextStyle(color: AppColors.textLight)));
}
