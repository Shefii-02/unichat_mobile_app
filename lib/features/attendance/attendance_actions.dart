import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:unichat_mobile_app/core/network/api.dart';
import 'package:unichat_mobile_app/core/theme/app_theme.dart';
import 'package:unichat_mobile_app/features/attendance/selfie_capture_page.dart';
import 'package:unichat_mobile_app/features/attendance/widgets/blur_loading_overlay.dart';

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

  // Re-read the company's selfie / geofence toggles right before punching, so a
  // change made on the web Office Details page applies immediately instead of
  // waiting for this screen's cached copy to refresh. Falls back to the cached one.
  try {
    final fresh = await Api.one('/hr/attendance/me');
    if (fresh['settings'] is Map) {
      settings = (fresh['settings'] as Map).cast<String, dynamic>();
    }
  } catch (_) {}

  if (action == 'clock_out') {
    if (!context.mounted) return false;
    final confirmed = await _confirmClockOut(context);
    if (!confirmed) return false;
  }

  // When the company enforces the office radius, location is mandatory: get it
  // up front (before the camera) so a missing GPS fix doesn't waste a selfie.
  final geoRequired = settings['geofence_mandatory'] == true;
  Position? position;
  if (geoRequired) {
    if (!context.mounted) return false;
    final locating = BlurLoadingOverlay.show(context, message: 'Getting your location…');
    position = await _bestEffortPosition();
    locating.hide();
    if (position == null) {
      if (context.mounted) await _locationRequiredDialog(context);
      return false;
    }
  }

  XFile? selfie;
  if (selfieRequiredFor(settings, action)) {
    if (!context.mounted) return false;
    final captured = await showDialog<XFile>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (_) => const SelfieCapturePage(),
    );
    if (captured == null) return false;
    selfie = captured;
  }

  if (!context.mounted) return false;
  final checking = BlurLoadingOverlay.show(context, message: 'Validating…');
  position ??= await _bestEffortPosition();

  String? note;
  String? radiusReason;

  Map<String, dynamic> check = const {};
  try {
    check = Map<String, dynamic>.from(await Api.post('/hr/attendance/precheck', data: {
      'action': action,
      if (position != null) 'lat': position.latitude,
      if (position != null) 'lng': position.longitude,
    }) as Map);
  } catch (_) {
    // Precheck is best-effort — the real submit's own validation (handled
    // below) still enforces the same rules if this call fails.
  }
  checking.hide();

  final radiusNeeded = check['radius_reason_needed'] == true;
  final noteNeeded = check['note_required'] == true;

  // One modal for everything the punch needs: the captured photo, the radius
  // result + message, and the note/reason field — instead of a chain of dialogs.
  if (selfie != null || geoRequired || radiusNeeded || noteNeeded) {
    if (!context.mounted) return false;
    final text = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      useRootNavigator: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _PunchReviewSheet(
        action: action,
        selfie: selfie,
        check: check,
        hasPosition: position != null,
      ),
    );
    if (text == null) return false;
    if (text.isNotEmpty) {
      if (radiusNeeded) radiusReason = text;
      if (noteNeeded || !radiusNeeded) note = text;
    }
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

    if (!context.mounted) return false;
    final submitting = BlurLoadingOverlay.show(context, message: 'Submitting…');
    try {
      await Api.raw.post(path, data: form);
      submitting.hide();
      return true;
    } on DioException catch (e) {
      submitting.hide();
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
      submitting.hide();
      if (context.mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
      }
      return false;
    }
  }
}

Future<void> _locationRequiredDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    useRootNavigator: true,
    builder: (ctx) => AlertDialog(
      title: const Text('Location required'),
      content: const Text(
        'Your company requires your location for attendance. Turn on location '
        'services and allow location access for this app, then try again.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(
          onPressed: () async {
            Navigator.pop(ctx);
            await Geolocator.openLocationSettings();
          },
          child: const Text('Open settings'),
        ),
      ],
    ),
  );
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

/// A day can have several clock-in/out sessions, so a slip is recoverable —
/// this just makes sure the clock-out is intentional.
Future<bool> _confirmClockOut(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: const Text('Clock out?'),
      content: const Text(
        'This ends your current session. If you clocked out by mistake, or '
        'start another shift later, just clock in again to open a new session.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Submit')),
      ],
    ),
  );
  return ok ?? false;
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


/// Bottom sheet shown after the selfie/GPS/precheck steps: the captured photo, the radius
/// verdict + message, and the note/reason field. Pops with the typed text ('' = none).
class _PunchReviewSheet extends StatefulWidget {
  const _PunchReviewSheet({
    required this.action,
    required this.selfie,
    required this.check,
    required this.hasPosition,
  });
  final String action;
  final XFile? selfie;
  final Map<String, dynamic> check;
  final bool hasPosition;

  @override
  State<_PunchReviewSheet> createState() => _PunchReviewSheetState();
}

class _PunchReviewSheetState extends State<_PunchReviewSheet> {
  final _controller = TextEditingController();
  bool _submitted = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  static const _titles = {
    'clock_in': 'Confirm clock in',
    'clock_out': 'Confirm clock out',
    'break_start': 'Confirm break start',
    'break_end': 'Confirm break end',
  };

  @override
  Widget build(BuildContext context) {
    final c = widget.check;
    final radiusNeeded = c['radius_reason_needed'] == true;
    final noteNeeded = c['note_required'] == true;
    final required = radiusNeeded || noteNeeded;
    final distance = c['distance_m'];
    final allowed = c['allowed_m'];

    final String radiusText;
    final Color radiusColor;
    if (radiusNeeded) {
      radiusText = '${c['radius_message'] ?? 'You are outside the office radius.'}';
      radiusColor = AppPalette.danger;
    } else if (distance != null) {
      radiusText = "Location verified — $distance m from the office (allowed: $allowed m).";
      radiusColor = Colors.green.shade700;
    } else {
      radiusText = widget.hasPosition ? 'Location captured.' : 'Location not available.';
      radiusColor = context.mutedColor;
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_titles[widget.action] ?? 'Confirm',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            if (widget.selfie != null)
              Center(
                child: ClipOval(
                  child: Image.file(File(widget.selfie!.path), width: 110, height: 110, fit: BoxFit.cover),
                ),
              ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(radiusNeeded ? Icons.location_off_rounded : Icons.location_on_rounded,
                    size: 18, color: radiusColor),
                const SizedBox(width: 8),
                Expanded(child: Text(radiusText, style: TextStyle(fontSize: 13, color: radiusColor))),
              ],
            ),
            if (noteNeeded) ...[
              const SizedBox(height: 8),
              Text('${c['note_message'] ?? 'A reason is required.'}',
                  style: TextStyle(fontSize: 13, color: AppPalette.danger)),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: required ? 'Reason (required)' : 'Note (optional)',
                hintText: 'e.g. Traffic delay',
                border: const OutlineInputBorder(),
                errorText: _submitted && required && _controller.text.trim().isEmpty
                    ? 'Please enter a reason'
                    : null,
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: () {
                      final v = _controller.text.trim();
                      if (required && v.isEmpty) {
                        setState(() => _submitted = true);
                        return;
                      }
                      Navigator.pop(context, v);
                    },
                    child: const Text('Submit'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
