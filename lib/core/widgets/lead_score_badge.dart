import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

class LeadScoreBadge extends StatelessWidget {
  const LeadScoreBadge({super.key, required this.score, this.large = false});

  final int score;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final color = AppColors.scoreColor(score);
    final emoji = score >= 76 ? '🔥' : score >= 51 ? '🌡' : score >= 26 ? '❄' : '🧊';
    final fontSize = large ? 14.0 : 11.0;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: large ? 10 : 6,
        vertical: large ? 5 : 3,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        '$emoji $score',
        style: TextStyle(color: color, fontSize: fontSize, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class StageBadge extends StatelessWidget {
  const StageBadge({super.key, required this.stage});
  final String stage;

  @override
  Widget build(BuildContext context) {
    final color = AppColors.stageColor(stage);
    final label = stage.replaceAll('_', ' ').toUpperCase();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700),
      ),
    );
  }
}
