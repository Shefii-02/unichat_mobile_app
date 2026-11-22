import 'package:unichat_mobile_app/core/widgets/teamzo_wordmark.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:unichat_mobile_app/core/constants/app_colors.dart';
import 'package:unichat_mobile_app/core/widgets/app_button.dart';
import 'package:unichat_mobile_app/features/auth/data/device_auth_repository.dart';
import 'package:unichat_mobile_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:unichat_mobile_app/features/auth/presentation/widgets/device_limit_sheet.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});
  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _emailCtrl = TextEditingController();
  final _passCtrl  = TextEditingController();
  bool _obscure    = true;
  final _form      = GlobalKey<FormState>();

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    await ref.read(authProvider.notifier).login(
      _emailCtrl.text.trim(),
      _passCtrl.text,
    );
    if (!mounted) return;
    final err = ref.read(authProvider).error;
    if (err is DeviceLimitException) {
      await _resolveDeviceLimit(err);
      return;
    }
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_errorMessage(err)), backgroundColor: AppColors.error),
      );
    }
    // success: the router sees the signed-in user and takes the app on (PIN prompt → clock-in gate → home)
  }

  /// The account is at its phone limit: list the phones, let the person remove one, repeat the sign-in — and on success the router
  /// carries on to the home screen by itself.
  Future<void> _resolveDeviceLimit(DeviceLimitException first) async {
    final email = _emailCtrl.text.trim();
    final password = _passCtrl.text;
    var current = first;
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => DeviceLimitSheet(
        limit: first,
        onRemove: (deviceId) async {
          try {
            final again = await ref.read(authProvider.notifier).removeDeviceAndRetry(
                  limit: current, deviceId: deviceId, email: email, password: password);
            if (again != null) { current = again; return DeviceLimitAgain(again); }
            return const DeviceLimitDone();
          } on DeviceChallengeException catch (e) {
            return DeviceLimitFailed(e.message);
          } catch (e) {
            return DeviceLimitFailed(_errorMessage(e));
          }
        },
      ),
    );
  }

  String _errorMessage(Object err) {
    final s = err.toString();
    // the admin switched this person's phone access off
    if (err is DioException && err.response?.data is Map && (err.response!.data as Map)['error_code'] == 'mobile_access_disabled') {
      return 'Mobile app access is disabled for your account.';
    }
    if (s.contains('401') || s.contains('422')) return 'Invalid email or password.';
    if (s.contains('Connection') || s.contains('SocketException')) return 'No internet connection.';
    return 'Login failed. Please try again.';
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = ref.watch(authProvider).isLoading;

    return Scaffold(
      body: Column(
        children: [
          Container(
            height: 250,
            width: double.infinity,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.primaryDark, AppColors.primary],
              ),
            ),
            child: SafeArea(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: Image.asset('assets/logo/teamzo-icon-tight.png', width: 72, height: 72),
                  ),
                  const SizedBox(height: 12),
                  const TeamzoWordmark(size: 32, color: Colors.white, accent: Color(0xFFD9DE4B)),
                  const Text('One team. One app.', style: TextStyle(color: Colors.white70, fontSize: 13)),
                ],
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 8),
                    _field(
                      controller: _emailCtrl,
                      label: 'Email',
                      hint: 'you@example.com',
                      icon: Icons.email_outlined,
                      keyboardType: TextInputType.emailAddress,
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Required';
                        if (!v.contains('@')) return 'Enter a valid email';
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    _field(
                      controller: _passCtrl,
                      label: 'Password',
                      hint: '••••••••',
                      icon: Icons.lock_outline,
                      obscure: _obscure,
                      suffix: IconButton(
                        icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility, color: AppColors.textLight),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                      validator: (v) => (v?.isEmpty ?? true) ? 'Required' : null,
                    ),
                    const SizedBox(height: 28),
                    AppButton(
                      label: 'Login',
                      onPressed: _submit,
                      loading: isLoading,
                      expand: true,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    bool obscure = false,
    Widget? suffix,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscure,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: AppColors.textLight, size: 20),
        suffixIcon: suffix,
      ),
      validator: validator,
    );
  }
}
