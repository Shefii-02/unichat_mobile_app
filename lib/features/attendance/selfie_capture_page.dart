import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

/// Selfie camera screen: live front-camera preview at its normal aspect ratio, a shutter button, and — once a shot is taken — a
/// review step with Retake / OK before the photo is handed back to the
/// caller. Pushed with `Navigator.push<XFile>`; returns null if cancelled.
class SelfieCapturePage extends StatefulWidget {
  const SelfieCapturePage({super.key});

  @override
  State<SelfieCapturePage> createState() => _SelfieCapturePageState();
}

class _SelfieCapturePageState extends State<SelfieCapturePage> {
  CameraController? _controller;
  XFile? _captured;
  String? _error;
  bool _initializing = true;
  bool _capturing = false;

  /// Opening the camera can hang (another app is using it, a permission prompt was dismissed) — never leave the person on a spinner.
  static const cameraOpenLimit = Duration(seconds: 12);

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    setState(() { _initializing = true; _error = null; });
    try {
      final cameras = await availableCameras().timeout(cameraOpenLimit);
      if (cameras.isEmpty) {
        setState(() {
          _error = 'No camera available on this device.';
          _initializing = false;
        });
        return;
      }
      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      final controller =
          CameraController(front, ResolutionPreset.medium, enableAudio: false);
      await controller.initialize().timeout(cameraOpenLimit, onTimeout: () {
        controller.dispose();
        throw TimeoutException('camera did not open');
      });
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _initializing = false;
      });
    } on TimeoutException {
      if (mounted) {
        setState(() {
          _error = 'The camera is taking too long to open. Close other apps that use the camera, then try again.';
          _initializing = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Could not open the camera. Check camera permission in Settings.';
          _initializing = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _capture() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized || c.value.isTakingPicture || _capturing) return;
    setState(() { _capturing = true; _error = null; });
    try {
      final file = await c.takePicture().timeout(const Duration(seconds: 8));
      if (mounted) setState(() { _captured = file; _capturing = false; });
    } catch (_) {
      // say so — a silent failure looked like a dead Capture button
      if (mounted) setState(() { _capturing = false; _notice = 'Could not take the photo — please try again.'; });
    }
  }

  String? _notice;

  void _retake() => setState(() => _captured = null);

  @override
  Widget build(BuildContext context) {
    // Modal card (same look as the web "Take a selfie" dialog) — shown via showDialog.
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_captured == null ? '📷 Take a selfie' : '📷 Use this photo?',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: ColoredBox(color: Colors.black, child: Center(child: _frame())),
            ),
            if (_notice != null && _captured == null) ...[
              const SizedBox(height: 10),
              Text(_notice!, key: const ValueKey('selfie-notice'), style: const TextStyle(color: Colors.red, fontSize: 13)),
            ],
            const SizedBox(height: 14),
            _actions(),
          ],
        ),
      ),
    );
  }

  /// The app theme makes every FilledButton "full width × 52" (`minimumSize: Size.fromHeight(52)`). Inside this dialog's Row that means an
  /// INFINITE width, so the dialog failed to lay out and the selfie screen never appeared. Give these buttons a normal, content-sized minimum.
  static final _buttonStyle = FilledButton.styleFrom(minimumSize: const Size(0, 44));

  Widget _actions() {
    if (_captured != null) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(onPressed: _retake, child: const Text('Retake')),
          const SizedBox(width: 8),
          FilledButton(
            style: _buttonStyle,
            onPressed: () => Navigator.pop(context, _captured),
            child: const Text('Use photo'),
          ),
        ],
      );
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        const SizedBox(width: 8),
        if (_error == null)
          FilledButton(
            style: _buttonStyle,
            key: const ValueKey('selfie-capture'),
            onPressed: (_initializing || _capturing) ? null : () { _notice = null; _capture(); },
            child: _capturing
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Capture'),
          )
        else
          FilledButton(style: _buttonStyle, key: const ValueKey('selfie-retry'), onPressed: _init, child: const Text('Try again')),
      ],
    );
  }

  Widget _frame() {
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text(_error!,
            textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
      );
    }
    final c = _controller;
    if (_initializing || c == null || !c.value.isInitialized) {
      return const SizedBox(
        height: 260,
        child: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }
    final ratio = 1 / c.value.aspectRatio;
    return AspectRatio(
      aspectRatio: ratio,
      child: _captured != null
          ? Image.file(File(_captured!.path), fit: BoxFit.cover)
          : Transform.scale(scaleX: -1, child: CameraPreview(c)),
    );
  }
}
