// ignore_for_file: use_build_context_synchronously
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:overlay_support/overlay_support.dart';
import 'package:unichat_mobile_app/core/constants/app_colors.dart';
import 'package:unichat_mobile_app/core/network/dio_client.dart';
import 'package:unichat_mobile_app/core/socket/socket_service.dart';

class LeadNotificationService {
  static StreamSubscription? _sub;

  static void start(BuildContext context) {
    _sub?.cancel();
    _sub = SocketService().leadNotifications.listen((data) {
      _showLeadNotification(context, data);
    });
  }

  static void stop() => _sub?.cancel();

  static void _showLeadNotification(BuildContext context, Map<String, dynamic> data) {
    final assignmentId = data['assignment_id'] as int?;
    final name    = data['contact_name'] as String? ?? 'New Contact';
    final phone   = data['contact_phone'] as String? ?? '';
    final score   = data['lead_score'] as int? ?? 0;
    final campaign= data['campaign_name'] as String? ?? '';

    showOverlayNotification(
      (ctx) => _LeadNotificationCard(
        assignmentId: assignmentId,
        name: name,
        phone: phone,
        score: score,
        campaign: campaign,
      ),
      duration: const Duration(seconds: 60),
      position: NotificationPosition.top,
    );
  }
}

class _LeadNotificationCard extends StatefulWidget {
  const _LeadNotificationCard({
    required this.assignmentId,
    required this.name,
    required this.phone,
    required this.score,
    required this.campaign,
  });

  final int? assignmentId;
  final String name;
  final String phone;
  final int score;
  final String campaign;

  @override
  State<_LeadNotificationCard> createState() => _LeadNotificationCardState();
}

class _LeadNotificationCardState extends State<_LeadNotificationCard> with SingleTickerProviderStateMixin {
  int _seconds = 60;
  Timer? _timer;
  late AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _seconds--);
      if (_seconds <= 0) {
        _decline(timeout: true);
        OverlaySupportEntry.of(context)?.dismiss();
      }
    });
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 600))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _accept() async {
    _timer?.cancel();
    if (widget.assignmentId != null) {
      try {
        await DioClient.laravelDio.post('/leads/${widget.assignmentId}/accept');
      } catch (_) {}
    }
    if (mounted) OverlaySupportEntry.of(context)?.dismiss();
  }

  void _decline({bool timeout = false}) {
    _timer?.cancel();
    if (widget.assignmentId != null) {
      final body = timeout ? {'reason': 'timeout'} : <String, dynamic>{};
      DioClient.laravelDio.post('/leads/${widget.assignmentId}/decline', data: body).ignore();
    }
    if (mounted) OverlaySupportEntry.of(context)?.dismiss();
  }

  @override
  Widget build(BuildContext context) {
    final color = AppColors.scoreColor(widget.score);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Card(
          elevation: 8,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(12),
                decoration: const BoxDecoration(
                  color: AppColors.primaryDark,
                  borderRadius: BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16)),
                ),
                child: Row(
                  children: [
                    const Text('🔔', style: TextStyle(fontSize: 18)),
                    const SizedBox(width: 8),
                    const Text('New Lead!', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
                    const Spacer(),
                    GestureDetector(onTap: () => _decline(), child: const Icon(Icons.close, color: Colors.white60, size: 18)),
                  ],
                ),
              ),

              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text('👤', style: TextStyle(fontSize: 16)),
                        const SizedBox(width: 8),
                        Text(widget.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Text('📱', style: TextStyle(fontSize: 14)),
                        const SizedBox(width: 8),
                        Text(widget.phone, style: const TextStyle(color: AppColors.textSecondary)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(color: color.withAlpha(20), borderRadius: BorderRadius.circular(8)),
                          child: Text('Score: ${widget.score}', style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
                        ),
                        if (widget.campaign.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Text('📢 ${widget.campaign}', style: const TextStyle(color: AppColors.textLight, fontSize: 12)),
                        ],
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Countdown bar
                    LinearProgressIndicator(
                      value: _seconds / 60,
                      backgroundColor: AppColors.bgGray,
                      valueColor: AlwaysStoppedAnimation(_seconds > 20 ? AppColors.success : AppColors.error),
                      minHeight: 6,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('⏱ ${_seconds}s remaining', style: const TextStyle(fontSize: 11, color: AppColors.textLight)),
                    ),

                    const SizedBox(height: 12),

                    // Buttons
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => _decline(),
                            style: OutlinedButton.styleFrom(foregroundColor: AppColors.error, side: const BorderSide(color: AppColors.error)),
                            child: const Text('❌ Decline'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: AnimatedBuilder(
                            animation: _pulse,
                            builder: (_, child) => Transform.scale(scale: 1.0 + _pulse.value * 0.04, child: child),
                            child: ElevatedButton(
                              onPressed: _accept,
                              style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
                              child: const Text('✅ Accept', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
