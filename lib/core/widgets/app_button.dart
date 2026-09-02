import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

enum AppButtonVariant { primary, secondary, danger, ghost }

class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.loading = false,
    this.icon,
    this.expand = false,
    this.small = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final bool loading;
  final IconData? icon;
  final bool expand;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final colors = switch (variant) {
      AppButtonVariant.primary   => (bg: AppColors.primary, fg: Colors.white),
      AppButtonVariant.secondary => (bg: Colors.white, fg: AppColors.primary),
      AppButtonVariant.danger    => (bg: AppColors.error, fg: Colors.white),
      AppButtonVariant.ghost     => (bg: Colors.transparent, fg: AppColors.primary),
    };
    final h = small ? 36.0 : 48.0;
    final child = loading
        ? SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: colors.fg),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[Icon(icon, size: 18, color: colors.fg), const SizedBox(width: 6)],
              Text(label, style: TextStyle(color: colors.fg, fontWeight: FontWeight.w700)),
            ],
          );

    final btn = ElevatedButton(
      onPressed: loading ? null : onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: colors.bg,
        foregroundColor: colors.fg,
        minimumSize: Size(small ? 80 : 120, h),
        side: variant == AppButtonVariant.secondary
            ? const BorderSide(color: AppColors.primary)
            : null,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: variant == AppButtonVariant.ghost ? 0 : 1,
      ),
      child: child,
    );

    return expand ? SizedBox(width: double.infinity, child: btn) : btn;
  }
}
