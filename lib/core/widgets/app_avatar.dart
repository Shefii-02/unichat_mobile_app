import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../constants/app_colors.dart';
import '../utils/format_utils.dart';

class AppAvatar extends StatelessWidget {
  const AppAvatar({
    super.key,
    this.name,
    this.imageUrl,
    this.size = 44,
    this.backgroundColor,
  });

  final String? name;
  final String? imageUrl;
  final double size;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final initials = FormatUtils.initials(name);
    final bg = backgroundColor ?? _colorFromName(name ?? '');

    if (imageUrl != null && imageUrl!.isNotEmpty) {
      return ClipOval(
        child: CachedNetworkImage(
          imageUrl: imageUrl!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorWidget: (_, __, ___) => _fallback(initials, bg),
          placeholder: (_, __) => _fallback(initials, bg),
        ),
      );
    }
    return _fallback(initials, bg);
  }

  Widget _fallback(String initials, Color bg) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.35,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  static const _colors = [
    Color(0xFF128C7E), Color(0xFF25D366), Color(0xFF34B7F1),
    Color(0xFFFF9500), Color(0xFFFF3B30), Color(0xFF9C27B0),
    Color(0xFF3F51B5), Color(0xFF795548),
  ];

  static Color _colorFromName(String name) {
    if (name.isEmpty) return AppColors.primary;
    return _colors[name.codeUnitAt(0) % _colors.length];
  }
}
