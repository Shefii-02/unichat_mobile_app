import 'package:flutter/material.dart';

/// Fixed brand palette from the approved "CRM Staff App" mockup — used for the hero
/// header, attendance card, stat/pipeline/follow-up tiles and other pastel accent blocks
/// across Home, Leads, Target, Attendance, Payroll and Profile. Shared here (rather than
/// duplicated per screen) so every screen stays visually consistent and a palette tweak
/// only needs to happen once. Structural chrome (borders, muted/body text) stays on the
/// app's theme tokens (see `app_theme.dart`), matching how the mockup itself used CSS
/// variables for those parts.
class M {
  M._();

  static const heroBg = Color(0xFF26215C);
  static const heroAvatarBg = Color(0xFF7F77DD);
  static const heroAvatarText = Color(0xFFEEEDFE);
  static const heroMuted = Color(0xFFCECBF6);
  static const heroRing = Color(0xFF7F77DD);
  static const heroDot = Color(0xFFF0997B);

  static const attBg = Color(0xFFE1F5EE);
  static const attDot = Color(0xFF1D9E75);
  static const attTitle = Color(0xFF04342C);
  static const attMuted = Color(0xFF0F6E56);
  static const attBtnBorder = Color(0xFF5DCAA5);

  static const peachBg = Color(0xFFFAECE7);
  static const peachTitle = Color(0xFF4A1B0C);
  static const peachMuted = Color(0xFF993C1D);

  static const blueBg = Color(0xFFE6F1FB);
  static const blueTitle = Color(0xFF042C53);
  static const blueMuted = Color(0xFF185FA5);

  static const amberBg = Color(0xFFFAEEDA);
  static const amberTitle = Color(0xFF412402);
  static const amberMuted = Color(0xFF854F0B);

  static const lavenderBg = Color(0xFFEEEDFE);
  static const lavenderTitle = Color(0xFF26215C);
  static const lavenderMuted = Color(0xFF534AB7);
  static const lavenderIconBg = Color(0xFFAFA9EC);

  static const redBg = Color(0xFFFCEBEB);
  static const redTitle = Color(0xFF501313);
  static const redMuted = Color(0xFFA32D2D);

  static const pinkBg = Color(0xFFFBEAF0);
  static const pinkTitle = Color(0xFF4B1528);
  static const pinkMuted = Color(0xFF993556);
  static const pinkSolid = Color(0xFF993556);

  static const taskDoneBg = Color(0xFF639922);
  static const priorityHigh = Color(0xFFD85A30);
  static const priorityMed = Color(0xFFEF9F27);

  static const gold = Color(0xFFFAC775);
  static const goldTitle = Color(0xFF412402);
}

/// A pastel (bg, title, muted) triple, matching one of the mockup's tile colours.
typedef Tint = (Color bg, Color title, Color muted);

const tintPeach = (M.peachBg, M.peachTitle, M.peachMuted);
const tintBlue = (M.blueBg, M.blueTitle, M.blueMuted);
const tintAmber = (M.amberBg, M.amberTitle, M.amberMuted);
const tintGreen = (M.attBg, M.attTitle, M.attMuted);
const tintLavender = (M.lavenderBg, M.lavenderTitle, M.lavenderMuted);
const tintRed = (M.redBg, M.redTitle, M.redMuted);

/// "9:14 AM" style 12-hour clock, matching the mockup's time formatting.
String time12(Object? v) {
  final d = DateTime.tryParse('${v ?? ''}');
  if (d == null) return '$v';
  final l = d.toLocal();
  final h12 = l.hour % 12 == 0 ? 12 : l.hour % 12;
  final ampm = l.hour < 12 ? 'AM' : 'PM';
  return '$h12:${l.minute.toString().padLeft(2, '0')} $ampm';
}
