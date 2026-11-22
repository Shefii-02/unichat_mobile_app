import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:unichat_mobile_app/core/theme/mockup_palette.dart';
import 'package:unichat_mobile_app/core/constants/api_constants.dart';
import 'package:unichat_mobile_app/features/auth/data/models/user_model.dart';
import 'package:unichat_mobile_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:unichat_mobile_app/features/modules/_shared.dart';

/// Edit photo/name/phone via the existing `PUT /auth/profile` (email isn't editable there —
/// it's tied to login identity, so it's shown read-only here rather than silently ignored).
class EditProfilePage extends ConsumerStatefulWidget {
  const EditProfilePage({super.key});
  @override
  ConsumerState<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends ConsumerState<EditProfilePage> {
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  XFile? _newAvatar;
  bool _busy = false;
  bool _initialised = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _curCtrl.dispose();
    _newCtrl.dispose();
    _confCtrl.dispose();
    super.dispose();
  }

  void _initFrom(user) {
    if (_initialised) return;
    _initialised = true;
    _nameCtrl.text = user.name;
    _phoneCtrl.text = user.phone;
  }

  Future<void> _pickAvatar() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (file != null) setState(() => _newAvatar = file);
  }

  Future<void> _save() async {
    final user = ref.read(authProvider).value;
    if (user == null) return;
    setState(() => _busy = true);
    try {
      final form = FormData.fromMap({
        '_method': 'PUT',
        'name': _nameCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
        if (_newAvatar != null)
          'avatar': await MultipartFile.fromFile(
            _newAvatar!.path,
            filename: _newAvatar!.name,
          ),
      });
      final res = await Api.raw.post('/auth/profile', data: form);
      final userJson =
          (res.data is Map) ? (res.data as Map)['user'] as Map? : null;
      // `updateProfile` returns a bare `fresh()` user (no `role`/`company` relations loaded,
      // unlike `profile()`), so merge only the fields that changed onto the cached model
      // rather than re-parsing the whole thing via UserModel.fromJson — that would blank
      // role/company on the object we're holding in memory.
      final updated = UserModel(
        id: user.id,
        name: userJson?['name'] as String? ?? _nameCtrl.text.trim(),
        phone: userJson?['phone'] as String? ?? _phoneCtrl.text.trim(),
        email: user.email,
        avatar: userJson?['avatar'] as String? ?? user.avatar,
        role: user.role,
        companyId: user.companyId,
        companyName: user.companyName,
        companySlug: user.companySlug,
        waContactToken: user.waContactToken,
        permissions: user.permissions,
      );
      ref.read(authProvider.notifier).adopt(updated);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Profile updated.')));
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).value;
    if (user == null)
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    _initFrom(user);

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Personal details'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Personal'),
              Tab(text: 'Work'),
              Tab(text: 'Security'),
            ],
          ),
        ),
        body: TabBarView(
          children: [_personalTab(user), _workTab(user), _securityTab()],
        ),
      ),
    );
  }

  Widget _personalTab(UserModel user) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Center(
          child: GestureDetector(
            onTap: _pickAvatar,
            child: Stack(
              children: [
                CircleAvatar(
                  radius: 44,
                  backgroundColor: M.heroAvatarBg,
                  backgroundImage:
                      _newAvatar != null
                          ? FileImage(File(_newAvatar!.path)) as ImageProvider
                          : (resolveStorageUrl(user.avatar) != null
                              ? NetworkImage(resolveStorageUrl(user.avatar)!)
                              : null),
                  child:
                      (_newAvatar == null &&
                              (user.avatar == null || user.avatar!.isEmpty))
                          ? Text(
                            user.name.isNotEmpty
                                ? user.name[0].toUpperCase()
                                : '?',
                            style: const TextStyle(
                              fontSize: 26,
                              color: M.heroAvatarText,
                            ),
                          )
                          : null,
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.edit_rounded,
                      size: 14,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text('Name', style: TextStyle(fontSize: 12, color: context.mutedColor)),
        const SizedBox(height: 6),
        TextField(controller: _nameCtrl, decoration: const InputDecoration()),
        const SizedBox(height: 16),
        Text(
          'Phone',
          style: TextStyle(fontSize: 12, color: context.mutedColor),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _phoneCtrl,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(),
        ),
        const SizedBox(height: 16),
        Text(
          'Email',
          style: TextStyle(fontSize: 12, color: context.mutedColor),
        ),
        const SizedBox(height: 6),
        TextField(
          enabled: false,
          controller: TextEditingController(text: user.email ?? '—'),
          decoration: const InputDecoration(),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            'Email can\'t be changed here — contact your admin.',
            style: TextStyle(fontSize: 11, color: context.mutedColor),
          ),
        ),
        const SizedBox(height: 28),
        FilledButton(
          onPressed: _busy ? null : _save,
          child:
              _busy
                  ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                  : const Text('Save changes'),
        ),
      ],
    );
  }

  String _pretty(String s) => s
      .split('_')
      .where((w) => w.isNotEmpty)
      .map((w) => '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
          child: Text(
            label,
            style: TextStyle(fontSize: 12, color: context.mutedColor),
          ),
        ),
        Expanded(
          child: Text(
            value.isEmpty ? '—' : value,
            style: const TextStyle(fontSize: 13.5),
          ),
        ),
      ],
    ),
  );

  /// What the company has set up for you — read-only, changed by an admin.
  Widget _workTab(UserModel user) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _row('Company', user.companyName ?? ''),
        const Divider(height: 1),
        _row('Role', _pretty(user.role)),
        const Divider(height: 1),
        _row('Email', user.email ?? ''),
        const Divider(height: 1),
        _row('Sections', user.accessSections.map(_pretty).join(', ')),
        const SizedBox(height: 16),
        Text(
          'These are set by your company admin. Ask them if something looks wrong.',
          style: TextStyle(fontSize: 11.5, color: context.mutedColor),
        ),
      ],
    );
  }

  final _curCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confCtrl = TextEditingController();
  bool _pwBusy = false;

  Future<void> _changePassword() async {
    if (_newCtrl.text.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('New password must be at least 8 characters.'),
        ),
      );
      return;
    }
    setState(() => _pwBusy = true);
    final ok = await runAction(
      context,
      () => Api.post(
        '/auth/change-password',
        data: {
          'current_password': _curCtrl.text,
          'password': _newCtrl.text,
          'password_confirmation': _confCtrl.text,
        },
      ),
      success: 'Password changed.',
    );
    if (mounted) setState(() => _pwBusy = false);
    if (ok) {
      _curCtrl.clear();
      _newCtrl.clear();
      _confCtrl.clear();
    }
  }

  Widget _securityTab() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Change password',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _curCtrl,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Current password'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _newCtrl,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'New password'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _confCtrl,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Confirm new password'),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _pwBusy ? null : _changePassword,
          child:
              _pwBusy
                  ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                  : const Text('Update password'),
        ),
        const SizedBox(height: 24),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.pin_outlined),
          title: const Text(
            'Change App Lock PIN',
            style: TextStyle(fontSize: 14),
          ),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => context.push('/change-mpin'),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.devices_rounded),
          title: const Text('Linked devices', style: TextStyle(fontSize: 14)),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => context.push('/devices'),
        ),
      ],
    );
  }
}
