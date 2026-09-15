import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:unichat_mobile_app/core/network/api.dart';
import 'package:unichat_mobile_app/core/theme/app_theme.dart';
import 'package:unichat_mobile_app/features/attendance/selfie_capture_page.dart';

const Map<String, String> _attendancePaths = {
  'clock_in': '/hr/attendance/clock-in',
  'clock_out': '/hr/attendance/clock-out',
  'break_start': '/hr/attendance/break/start',
  'break_end': '/hr/attendance/break/end',
};

/// Whether `settings` (the `settings` object nested in `/hr/attendance/me`)
/// requires a selfie for this specific punch action — each action's toggle
/// is independent, and the whole step is skipped when its toggle is off.
bool selfieRequiredFor(Map<String, dynamic> settings, String action) {
  return settings['selfie_required_$action'] == true;
}

/// Runs one HR attendance action (clock in/out, break start/end):
/// 1. If this action's selfie toggle is on, opens the round selfie-capture
///    screen (capture → retake → OK) — cancelling it cancels the action.
/// 2. Captures the device's GPS position, best-effort.
/// 3. Calls `/hr/attendance/precheck` (a dry run, nothing is written yet) so
///    a late/early-leave note or an out-of-radius reason gets asked for
///    proactively, before submitting — each check only runs if the company
///    has that setting turned on; if precheck can't be reached, it's skipped
///    and the actual submit's own validation below still catches it.
/// 4. Submits, and if the backend still comes back asking for a reason
///    (a race between precheck and submit, or precheck being unreachable),
///    prompts for it and retries automatically.
Future<bool> attendanceAction(
  BuildContext context, {
  required String action,
  required Map<String, dynamic> settings,
}) async {
  final path = _attendancePaths[action];
  if (path == null) return false;

  XFile? selfie;
  if (selfieRequiredFor(settings, action)) {
    if (!context.mounted) return false;
    final captured = await Navigator.of(context, rootNavigator: true).push<XFile>(
      MaterialPageRoute(builder: (_) => const SelfieCapturePage(), fullscreenDialog: true),
    );
    if (captured == null) return false;
    selfie = captured;
  }

  final position = await _bestEffortPosition();

  String? note;
  String? radiusReason;

  try {
    final check = await Api.post('/hr/attendance/precheck', data: {
      'action': action,
      if (position != null) 'lat': position.latitude,
      if (position != null) 'lng': position.longitude,
    });
    if (check['radius_reason_needed'] == true) {
      if (!context.mounted) return false;
      final reason = await _askReason(context,
          '${check['radius_message'] ?? 'You are outside the office radius.'}');
      if (reason == null) return false;
      radiusReason = reason;
    }
    if (check['note_required'] == true) {
      if (!context.mounted) return false;
      final reason =
          await _askReason(context, '${check['note_message'] ?? 'A reason is required.'}');
      if (reason == null) return false;
      note = reason;
    }
  } catch (_) {
    // Precheck is best-effort — the real submit's own validation (handled
    // below) still enforces the same rules if this call fails.
  }

  while (true) {
    final form = FormData.fromMap({
      if (selfie != null)
        'selfie': await MultipartFile.fromFile(selfie.path, filename: selfie.name),
      if (position != null) 'lat': position.latitude,
      if (position != null) 'lng': position.longitude,
      if (note != null) 'note': note,
      if (radiusReason != null) 'radius_reason': radiusReason,
    });

    try {
      await Api.raw.post(path, data: form);
      return true;
    } on DioException catch (e) {
      final body = e.response?.data;
      final errors = body is Map ? body['errors'] : null;

      final noteErrors = errors is Map ? errors['note'] : null;
      if (note == null && noteErrors is List && noteErrors.isNotEmpty) {
        if (!context.mounted) return false;
        final reason = await _askReason(context, '${noteErrors.first}');
        if (reason == null) return false;
        note = reason;
        continue;
      }

      final radiusErrors = errors is Map ? errors['radius_reason'] : null;
      if (radiusReason == null && radiusErrors is List && radiusErrors.isNotEmpty) {
        if (!context.mounted) return false;
        final reason = await _askReason(context, '${radiusErrors.first}');
        if (reason == null) return false;
        radiusReason = reason;
        continue;
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
      }
      return false;
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
      }
      return false;
    }
  }
}

Future<Position?> _bestEffortPosition() async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return null;
    }
    return await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 12),
      ),
    );
  } catch (_) {
    return null;
  }
}

Future<String?> _askReason(BuildContext context, String message) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: const Text('Reason needed'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message, style: TextStyle(color: ctx.mutedColor)),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            autofocus: true,
            maxLines: 2,
            decoration: const InputDecoration(
              hintText: 'e.g. Traffic delay',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final v = controller.text.trim();
            if (v.isEmpty) return;
            Navigator.pop(ctx, v);
          },
          child: const Text('Submit'),
        ),
      ],
    ),
  );
}
