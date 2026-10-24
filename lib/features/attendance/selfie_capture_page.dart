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

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final cameras = await availableCameras();
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
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _initializing = false;
      });
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
    if (c == null || !c.value.isInitialized || c.value.isTakingPicture) return;
    try {
      final file = await c.takePicture();
      if (mounted) setState(() => _captured = file);
    } catch (_) {
      // shutter glitch — let them try again
    }
  }

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
            const SizedBox(height: 14),
            _actions(),
          ],
        ),
      ),
    );
  }

  Widget _actions() {
    if (_captured != null) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(onPressed: _retake, child: const Text('Retake')),
          const SizedBox(width: 8),
          FilledButton(
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
            onPressed: _initializing ? null : _capture,
            child: const Text('Capture'),
          ),
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
