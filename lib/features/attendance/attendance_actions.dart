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

/// Must THIS person share their location before punching? The server works it out per person
/// (`geo_required`: the company enforces the office radius, they are GPS-tracked and working from the office today).
/// The company-wide `geofence_mandatory` switch alone is not enough — it used to block work-from-home and non-GPS
/// colleagues with "Location required". An older server without `geo_required` falls back to the old switch.
bool geoRequiredFor(Map<String, dynamic> settings) {
  if (settings.containsKey('geo_required')) return settings['geo_required'] == true;
  return settings['geofence_mandatory'] == true;
}

/// What the punch still has to ask once the selfie and location are done (from `/hr/attendance/precheck`).
enum PunchAsk {
  /// Nothing — submit straight away, no extra screen.
  nothing,

  /// Late and the company asks for a reason but lets you skip it.
  optionalNote,

  /// A reason must be typed: a late clock-in, an early / late clock-out, or a break that ran over.
  requiredNote,

  /// Outside the office radius (or no location) on a day the radius is enforced: alert + a reason.
  radiusReason,
}

/// Decides whether the review sheet is needed at all. The selfie is already confirmed on its own "Use this photo?" step, and a
/// punch that is on time and inside the radius has nothing to add — so no sheet, no empty "note" box, straight to the app.
PunchAsk punchAsk(Map<String, dynamic> check) {
  if (check['radius_reason_needed'] == true) return PunchAsk.radiusReason;
  if (check['note_required'] == true) return PunchAsk.requiredNote;
  if (check['note_optional'] == true) return PunchAsk.optionalNote;
  return PunchAsk.nothing;
}

/// One choice in the "which break?" list.
class BreakChoice {
  const BreakChoice({required this.id, required this.name, this.maxMinutes, this.dailyLimit, this.usedToday = 0});
  final int id;
  final String name;
  final int? maxMinutes;
  final int? dailyLimit;
  final int usedToday;

  /// A type with a daily limit that has been used up cannot be chosen again today.
  bool get exhausted => dailyLimit != null && usedToday >= dailyLimit!;

  String get detail {
    final parts = <String>[
      if (maxMinutes != null) 'up to $maxMinutes min',
      if (dailyLimit != null) '${(dailyLimit! - usedToday).clamp(0, dailyLimit!)} of $dailyLimit left today',
    ];
    return parts.join(' · ');
  }
}

/// The break types the company defined (`break_types` in `/hr/attendance/me`) with how often each was used today.
List<BreakChoice> breakChoices(Map<String, dynamic> me) {
  final types = me['break_types'] is List ? (me['break_types'] as List).whereType<Map>() : const <Map>[];
  final today = me['today'] is Map ? me['today'] as Map : const {};
  final breaks = today['breaks'] is List ? (today['breaks'] as List).whereType<Map>().toList() : const <Map>[];
  int? asInt(Object? v) => v == null ? null : int.tryParse('$v');
  return [
    for (final t in types)
      if (t['is_active'] != false && asInt(t['id']) != null)
        BreakChoice(
          id: asInt(t['id'])!,
          name: '${t['name'] ?? 'Break'}',
          maxMinutes: asInt(t['max_minutes']),
          dailyLimit: asInt(t['daily_limit']),
          usedToday: breaks.where((b) => asInt(b['break_type_id']) == asInt(t['id'])).length,
        ),
  ];
}

/// Runs one HR attendance action (clock in/out, break start/end):
/// 1. If this action's selfie toggle is on, opens the round selfie-capture
///    screen (capture → retake → OK) — cancelling it cancels the action.
/// 2. Captures the device's GPS position, best-effort (mandatory for staff who
///    must be at the office — see [geoRequiredFor]).
/// 3. Calls `/hr/attendance/precheck` (a dry run, nothing is written yet) so
///    a late/early-leave note or an out-of-radius reason gets asked for
///    proactively, before submitting — each check only runs if the company
///    has that setting turned on; if precheck can't be reached, it's skipped
///    and the actual submit's own validation below still catches it.
/// 4. Only if the precheck says something still needs asking (see [punchAsk]) shows the
///    review sheet; otherwise it submits straight away.
/// 5. Submits, and if the backend still comes back asking for a reason
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
  Map<String, dynamic> me = const {};
  try {
    final fresh = await Api.one('/hr/attendance/me');
    me = Map<String, dynamic>.from(fresh);
    if (fresh['settings'] is Map) {
      settings = (fresh['settings'] as Map).cast<String, dynamic>();
    }
  } catch (_) {}

  if (action == 'clock_out') {
    if (!context.mounted) return false;
    final confirmed = await _confirmClockOut(context);
    if (!confirmed) return false;
  }

  // When the company enforces the office radius for this person, location is mandatory: get it
  // up front (before the camera) so a missing GPS fix doesn't waste a selfie.
  final geoRequired = geoRequiredFor(settings);
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

  // Taking a break: which kind? (Only when the company defined break types — they carry the time and daily limits.)
  int? breakTypeId;
  if (action == 'break_start') {
    final choices = breakChoices(me);
    if (choices.isNotEmpty) {
      if (!context.mounted) return false;
      final picked = await _pickBreakType(context, choices);
      if (picked == null) return false;
      breakTypeId = picked;
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
  // not mandatory for this person: take a location if it is quick, but never make them wait for it
  position ??= await _bestEffortPosition(limit: const Duration(seconds: 5));

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

  final ask = punchAsk(check);
  final radiusNeeded = ask == PunchAsk.radiusReason;
  final noteNeeded = check['note_required'] == true;
  // company setting "Late clock-in reason = Optional": ask, but the person may skip
  final noteOptional = check['note_optional'] == true;

  // One modal for everything the punch still has to ask — the radius alert and/or the reason. When there is nothing to ask (on
  // time, inside the radius, or the late-reason setting is off) there is NO sheet and no empty note box: it submits straight away.
  if (ask != PunchAsk.nothing) {
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
      if (noteNeeded || noteOptional) note = text;
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
      if (breakTypeId != null) 'break_type_id': breakTypeId,
      'source': 'mobile',
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

/// "Which break?" — the company's break types with their time and daily limits; a type used up for today is greyed out.
Future<int?> _pickBreakType(BuildContext context, List<BreakChoice> choices) {
  return showModalBottomSheet<int>(
    context: context,
    useRootNavigator: true,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Which break?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
          ),
          for (final c in choices)
            ListTile(
              key: ValueKey('break-type-${c.id}'),
              enabled: !c.exhausted,
              leading: const Icon(Icons.free_breakfast_rounded),
              title: Text(c.name),
              subtitle: c.detail.isEmpty ? null : Text(c.exhausted ? 'Daily limit reached' : c.detail),
              onTap: c.exhausted ? null : () => Navigator.pop(ctx, c.id),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
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

Future<Position?> _bestEffortPosition({Duration limit = const Duration(seconds: 12)}) async {
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
      locationSettings: LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: limit,
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


/// Bottom sheet shown after the selfie/GPS/precheck steps — ONLY when the punch still has something to ask (see [punchAsk]): the
/// radius alert when the person is outside the office, and/or the reason field (required, or optional when the company allows
/// skipping a late reason). Shows the captured photo for context. Pops with the typed text ('' = none).
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
    final noteOptional = c['note_optional'] == true;
    final required = radiusNeeded || noteNeeded;

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
            // Geo alert: only when the person is outside the radius (or no location) — never shown for someone who is in range.
            if (radiusNeeded) ...[
              const SizedBox(height: 12),
              Container(
                key: const ValueKey('radius-alert'),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppPalette.danger.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppPalette.danger.withValues(alpha: 0.35)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.location_off_rounded, size: 18, color: AppPalette.danger),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${c['radius_message'] ?? 'You are outside the office radius.'} Add a reason to continue.',
                        style: const TextStyle(fontSize: 13, color: AppPalette.danger),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (noteNeeded) ...[
              const SizedBox(height: 10),
              Text('${c['note_message'] ?? 'A reason is required.'}',
                  key: const ValueKey('note-message'),
                  style: TextStyle(fontSize: 13, color: AppPalette.danger)),
            ] else if (noteOptional) ...[
              const SizedBox(height: 10),
              Text('${c['note_message'] ?? 'You can add a reason (optional).'}',
                  key: const ValueKey('note-message'),
                  style: TextStyle(fontSize: 13, color: Colors.orange.shade800)),
            ],
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('reason-field'),
              controller: _controller,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: required ? 'Reason (required)' : 'Reason for being late (optional)',
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
                    key: const ValueKey('punch-submit'),
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
