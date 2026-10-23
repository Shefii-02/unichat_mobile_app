import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// "teamzo" brand wordmark — Bricolage Grotesque 800 (DM Sans fallback), tight tracking, accented "zo".
class TeamzoWordmark extends StatelessWidget {
  const TeamzoWordmark({super.key, required this.size, this.color = const Color(0xFF14213D), this.accent = const Color(0xFF107F68)});
  final double size;
  final Color color, accent;

  @override
  Widget build(BuildContext context) {
    final base = GoogleFonts.bricolageGrotesque(
      fontWeight: FontWeight.w800,
      fontSize: size,
      height: 0.95,
      letterSpacing: -size * 4 / 132,
      color: color,
    ).copyWith(fontFamilyFallback: [GoogleFonts.dmSans().fontFamily!, 'sans-serif']);
    return Text.rich(TextSpan(style: base, children: [TextSpan(text: 'team'), TextSpan(text: 'zo', style: TextStyle(color: accent))]));
  }
}
