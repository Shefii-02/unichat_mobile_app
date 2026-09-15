import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

/// Round, selfie-verification-style camera screen: live front-camera preview
/// inside a circular frame, a shutter button, and — once a shot is taken — a
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
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.topLeft,
              child: IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _captured == null ? 'Position your face in the circle' : 'Use this photo?',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            Expanded(child: Center(child: _frame())),
            Padding(
              padding: const EdgeInsets.only(bottom: 32, top: 16),
              child: _captured == null ? _shutter() : _reviewActions(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _frame() {
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Text(_error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70)),
      );
    }
    if (_initializing) {
      return const CircularProgressIndicator(color: Colors.white);
    }

    const size = 280.0;
    Widget inner;
    if (_captured != null) {
      inner = Image.file(File(_captured!.path), fit: BoxFit.cover);
    } else {
      final c = _controller;
      inner = (c == null || !c.value.isInitialized)
          ? const SizedBox()
          : Transform.scale(scaleX: -1, child: CameraPreview(c));
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
      ),
      child: ClipOval(
        child: SizedBox(
          width: size,
          height: size,
          child: FittedBox(fit: BoxFit.cover, child: SizedBox(width: size, height: size, child: inner)),
        ),
      ),
    );
  }

  Widget _shutter() {
    if (_error != null || _initializing) return const SizedBox(height: 72);
    return GestureDetector(
      onTap: _capture,
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 4),
        ),
        child: Container(
          margin: const EdgeInsets.all(4),
          decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
        ),
      ),
    );
  }

  Widget _reviewActions() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white, side: const BorderSide(color: Colors.white)),
          onPressed: _retake,
          icon: const Icon(Icons.replay_rounded),
          label: const Text('Retake'),
        ),
        const SizedBox(width: 16),
        FilledButton.icon(
          onPressed: () => Navigator.pop(context, _captured),
          icon: const Icon(Icons.check_rounded),
          label: const Text('OK'),
        ),
      ],
    );
  }
}
