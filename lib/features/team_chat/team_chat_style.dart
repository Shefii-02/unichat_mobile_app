import 'dart:ui';
import 'package:flutter/material.dart';

/// Light-blue glassmorphism used across the team-chat screens: a soft blue gradient backdrop with blurred
/// colour blobs, frosted-glass panels (backdrop blur + translucent white + hairline border) and a calm blue
/// accent. Adapts to dark mode with a deep-navy variant.
class Glass {
  Glass._();

  static const accent = Color(0xFF3B82F6);
  static const accentSoft = Color(0xFF60A5FA);
  static const accentDeep = Color(0xFF1D4ED8);
  static const ice = Color(0xFFEAF4FF);

  static bool dark(BuildContext c) => Theme.of(c).brightness == Brightness.dark;

  static List<Color> backdrop(BuildContext c) => dark(c)
      ? const [Color(0xFF0B1220), Color(0xFF0F1B33), Color(0xFF0A1730)]
      : const [Color(0xFFE6F2FF), Color(0xFFF4F9FF), Color(0xFFDCEBFF)];

  static Color panel(BuildContext c, {double a = 0.55}) =>
      dark(c) ? const Color(0xFF16233D).withOpacity(a + 0.1) : Colors.white.withOpacity(a);

  static Color border(BuildContext c) =>
      dark(c) ? Colors.white.withOpacity(0.10) : Colors.white.withOpacity(0.85);

  static Color text(BuildContext c) => dark(c) ? const Color(0xFFE5EEFF) : const Color(0xFF0F2A4A);
  static Color muted(BuildContext c) => dark(c) ? const Color(0xFF93A8C9) : const Color(0xFF5B7597);

  /// Bubble colours: mine = light-blue glass, theirs = white glass.
  static Color bubbleMine(BuildContext c) => dark(c) ? const Color(0xFF1E4FA8).withOpacity(0.75) : const Color(0xFFCFE5FF).withOpacity(0.92);
  static Color bubbleTheirs(BuildContext c) => dark(c) ? const Color(0xFF1B2B4A).withOpacity(0.85) : Colors.white.withOpacity(0.88);
}

/// Full-screen blue gradient with blurred blobs — put it behind a transparent Scaffold.
class GlassBackground extends StatelessWidget {
  const GlassBackground({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = Glass.dark(context);
    return Stack(children: [
      Positioned.fill(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: Glass.backdrop(context)),
          ),
        ),
      ),
      Positioned(top: -70, right: -50, child: _blob(220, Glass.accentSoft.withOpacity(dark ? 0.18 : 0.30))),
      Positioned(top: 260, left: -90, child: _blob(240, const Color(0xFF93C5FD).withOpacity(dark ? 0.12 : 0.28))),
      Positioned(bottom: -80, right: -30, child: _blob(260, const Color(0xFFBFDBFE).withOpacity(dark ? 0.10 : 0.45))),
      Positioned.fill(child: child),
    ]);
  }

  Widget _blob(double size, Color c) => ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
        child: Container(width: size, height: size, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
      );
}

/// Frosted-glass panel.
class GlassCard extends StatelessWidget {
  const GlassCard({super.key, required this.child, this.padding = const EdgeInsets.all(12), this.radius = 20, this.blur = 14, this.opacity = 0.55, this.margin});
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final double radius, blur, opacity;

  @override
  Widget build(BuildContext context) => Container(
        margin: margin,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
            child: Container(
              padding: padding,
              decoration: BoxDecoration(
                color: Glass.panel(context, a: opacity),
                borderRadius: BorderRadius.circular(radius),
                border: Border.all(color: Glass.border(context), width: 1),
                boxShadow: [BoxShadow(color: Glass.accent.withOpacity(0.08), blurRadius: 24, offset: const Offset(0, 8))],
              ),
              child: child,
            ),
          ),
        ),
      );
}

/// Frosted app bar (blurred, translucent) for chat screens.
class GlassAppBar extends StatelessWidget implements PreferredSizeWidget {
  const GlassAppBar({super.key, this.title, this.leading, this.actions, this.bottom, this.titleSpacing});
  final Widget? title, leading;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;
  final double? titleSpacing;

  @override
  Size get preferredSize => Size.fromHeight(kToolbarHeight + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) => ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: AppBar(
            backgroundColor: Glass.panel(context, a: 0.5),
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            foregroundColor: Glass.text(context),
            leading: leading,
            title: title,
            titleSpacing: titleSpacing,
            actions: actions,
            bottom: bottom,
          ),
        ),
      );
}

/// Smooth, bouncy scrolling used by every list in the chat section.
const teamScrollPhysics = BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());

/// Round glass icon button / pill for quick actions.
class GlassPill extends StatelessWidget {
  const GlassPill({super.key, required this.icon, required this.label, required this.onTap, this.filled = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          decoration: BoxDecoration(
            gradient: filled ? const LinearGradient(colors: [Glass.accentSoft, Glass.accent]) : null,
            color: filled ? null : Glass.panel(context, a: 0.6),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: filled ? Colors.transparent : Glass.border(context)),
            boxShadow: filled ? [BoxShadow(color: Glass.accent.withOpacity(0.35), blurRadius: 14, offset: const Offset(0, 6))] : null,
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 18, color: filled ? Colors.white : Glass.accentDeep),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: filled ? Colors.white : Glass.text(context))),
          ]),
        ),
      );
}
