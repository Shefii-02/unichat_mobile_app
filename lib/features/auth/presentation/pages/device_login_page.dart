import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:pinput/pinput.dart';
import 'package:unichat_mobile_app/core/theme/app_theme.dart';
import 'package:unichat_mobile_app/features/auth/data/device_auth_repository.dart';
import 'package:unichat_mobile_app/features/auth/presentation/providers/device_login_controller.dart';

class DeviceLoginPage extends ConsumerStatefulWidget {
  const DeviceLoginPage({super.key});
  @override
  ConsumerState<DeviceLoginPage> createState() => _DeviceLoginPageState();
}

class _DeviceLoginPageState extends ConsumerState<DeviceLoginPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _scanner = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [BarcodeFormat.qrCode],
  );
  bool _handledScan = false;
  bool _sheetOpen = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _tabs.addListener(() {
      if (_tabs.indexIsChanging) {
        _handledScan = false;
        _tabs.index == 0 ? _scanner.start() : _scanner.stop();
      }
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    _scanner.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handledScan || _sheetOpen) return;
    for (final b in capture.barcodes) {
      final raw = b.rawValue;
      if (raw == null) continue;
      final token = DeviceAuthRepository.tokenFromQr(raw);
      if (token != null) {
        _handledScan = true;
        ref.read(deviceLoginControllerProvider.notifier).submit(token: token);
        return;
      }
    }
  }

  Future<void> _openConfirmSheet() async {
    _sheetOpen = true;
    await _scanner.stop();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const _ConfirmSheet(),
    );
    _sheetOpen = false;
    _handledScan = false;
    ref.read(deviceLoginControllerProvider.notifier).reset();
    if (mounted && _tabs.index == 0) _scanner.start();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(deviceLoginControllerProvider, (prev, next) {
      if (next.error != null && next.error != prev?.error) {
        _handledScan = false;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(next.error!)));
      }
      final entersConfirm = next.phase == DeviceLoginPhase.confirm ||
          next.phase == DeviceLoginPhase.claiming ||
          next.phase == DeviceLoginPhase.deviceLimit;
      if (entersConfirm && !_sheetOpen) {
        _openConfirmSheet();
      }
      if (next.phase == DeviceLoginPhase.done) {
        // Auth state flipped — the router redirect takes it from here.
        if (Navigator.of(context).canPop()) Navigator.of(context).pop();
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Link this device'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(icon: Icon(Icons.qr_code_scanner_rounded), text: 'Scan QR'),
            Tab(icon: Icon(Icons.pin_rounded), text: 'Enter PIN'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _QrTab(controller: _scanner, onDetect: _onDetect),
          const _PinTab(),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: TextButton(
          onPressed: () => context.push('/login'),
          child: const Text('Sign in with email & password instead'),
        ),
      ),
    );
  }
}

// ───────────────────────── QR tab ─────────────────────────

class _QrTab extends StatelessWidget {
  const _QrTab({required this.controller, required this.onDetect});
  final MobileScannerController controller;
  final void Function(BarcodeCapture) onDetect;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              MobileScanner(controller: controller, onDetect: onDetect),
              const _ScannerReticle(),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            'On the web app open  Settings → Devices → Link a device  and point '
            'your camera at the QR code. It refreshes every 45 seconds.',
            textAlign: TextAlign.center,
            style: TextStyle(color: context.mutedColor, fontSize: 13, height: 1.5),
          ),
        ),
      ],
    );
  }
}

class _ScannerReticle extends StatelessWidget {
  const _ScannerReticle();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 240,
        height: 240,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white, width: 3),
          borderRadius: BorderRadius.circular(24),
        ),
      ),
    );
  }
}

// ───────────────────────── PIN tab ─────────────────────────

class _PinTab extends ConsumerStatefulWidget {
  const _PinTab();
  @override
  ConsumerState<_PinTab> createState() => _PinTabState();
}

class _PinTabState extends ConsumerState<_PinTab> {
  final _pinController = TextEditingController();

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final busy = ref.watch(
        deviceLoginControllerProvider.select((s) => s.busy));

    final defaultPin = PinTheme(
      width: 48,
      height: 56,
      textStyle: theme.textTheme.titleLarge,
      decoration: BoxDecoration(
        color: context.altSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.lineColor),
      ),
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
      child: Column(
        children: [
          Icon(Icons.pin_rounded, size: 48, color: theme.colorScheme.primary),
          const SizedBox(height: 20),
          Text('Enter the 6-digit PIN',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(
            'Shown next to the QR code on the web app. The PIN changes every 45 seconds.',
            textAlign: TextAlign.center,
            style: TextStyle(color: context.mutedColor, fontSize: 13, height: 1.5),
          ),
          const SizedBox(height: 32),
          Pinput(
            controller: _pinController,
            length: 6,
            defaultPinTheme: defaultPin,
            focusedPinTheme: defaultPin.copyWith(
              decoration: defaultPin.decoration!.copyWith(
                border: Border.all(color: theme.colorScheme.primary, width: 1.6),
              ),
            ),
            keyboardType: TextInputType.number,
            onCompleted: (pin) => ref
                .read(deviceLoginControllerProvider.notifier)
                .submit(pin: pin),
          ),
          const SizedBox(height: 28),
          FilledButton(
            onPressed: busy || _pinController.text.length < 6
                ? null
                : () => ref
                    .read(deviceLoginControllerProvider.notifier)
                    .submit(pin: _pinController.text),
            child: busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Text('Continue'),
          ),
        ],
      ),
    );
  }
}

// ─────────────────── Confirm / device-limit sheet ───────────────────

class _ConfirmSheet extends ConsumerStatefulWidget {
  const _ConfirmSheet();
  @override
  ConsumerState<_ConfirmSheet> createState() => _ConfirmSheetState();
}

class _ConfirmSheetState extends ConsumerState<_ConfirmSheet> {
  Timer? _ticker;
  Duration _left = Duration.zero;

  @override
  void initState() {
    super.initState();
    final check = ref.read(deviceLoginControllerProvider).check;
    _left = check?.remaining ?? const Duration(seconds: 45);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _left -= const Duration(seconds: 1);
        if (_left.isNegative) _left = Duration.zero;
      });
      if (_left == Duration.zero) _ticker?.cancel();
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(deviceLoginControllerProvider);
    final ctrl = ref.read(deviceLoginControllerProvider.notifier);
    final expired = _left == Duration.zero;

    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 20,
        bottom: 24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: context.lineColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          if (state.phase == DeviceLoginPhase.deviceLimit)
            _deviceLimit(context, state, ctrl)
          else
            _confirm(context, theme, state, ctrl, expired),
        ],
      ),
    );
  }

  Widget _confirm(BuildContext context, ThemeData theme, DeviceLoginState state,
      DeviceLoginController ctrl, bool expired) {
    final name = state.check?.name ?? 'this account';
    final email = state.check?.email;
    final busy = state.phase == DeviceLoginPhase.claiming;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(
          radius: 30,
          backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.12),
          child: Text(
            name.isNotEmpty ? name[0].toUpperCase() : '?',
            style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.primary),
          ),
        ),
        const SizedBox(height: 14),
        Text('Sign in as $name',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700)),
        if (email != null) ...[
          const SizedBox(height: 3),
          Text(email, style: TextStyle(color: context.mutedColor)),
        ],
        const SizedBox(height: 18),
        if (expired)
          _expiredNote(context)
        else
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.timer_outlined, size: 16, color: context.mutedColor),
              const SizedBox(width: 6),
              Text('Code expires in ${_left.inSeconds}s',
                  style: TextStyle(color: context.mutedColor, fontSize: 13)),
            ],
          ),
        const SizedBox(height: 22),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: busy ? null : () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: (busy || expired) ? null : ctrl.confirm,
                child: busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('Sign in'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _expiredNote(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppPalette.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: AppPalette.warning, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'This code expired. Refresh it on the web and scan again.',
              style: TextStyle(color: context.mutedColor, fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _deviceLimit(BuildContext context, DeviceLoginState state,
      DeviceLoginController ctrl) {
    final theme = Theme.of(context);
    final limit = state.limit!;
    final busy = state.phase == DeviceLoginPhase.claiming;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.devices_other_rounded,
            size: 40, color: AppPalette.warning),
        const SizedBox(height: 12),
        Text('Device limit reached',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text(
          limit.message,
          textAlign: TextAlign.center,
          style: TextStyle(color: context.mutedColor, fontSize: 13, height: 1.4),
        ),
        const SizedBox(height: 16),
        ...limit.devices.map(
          (d) => Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: Icon(_platformIcon(d.platform)),
              title: Text(d.name),
              subtitle: Text(d.lastActiveAt != null
                  ? 'Last active ${_ago(d.lastActiveAt!)}'
                  : (d.platform ?? 'Unknown')),
              trailing: busy
                  ? null
                  : TextButton(
                      onPressed: () => ctrl.removeAndRetry(d.id),
                      child: const Text('Remove'),
                    ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        if (busy)
          const Padding(
            padding: EdgeInsets.all(8),
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        TextButton(
          onPressed: busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }

  IconData _platformIcon(String? p) {
    switch (p) {
      case 'ios':
        return Icons.phone_iphone_rounded;
      case 'android':
        return Icons.phone_android_rounded;
      case 'web':
        return Icons.language_rounded;
      default:
        return Icons.devices_rounded;
    }
  }

  String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inHours < 1) return '${d.inMinutes}m ago';
    if (d.inDays < 1) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }
}
