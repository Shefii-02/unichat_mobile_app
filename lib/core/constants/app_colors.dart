import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  static const primary        = Color(0xFF128C7E);
  static const primaryDark    = Color(0xFF075E54);
  static const primaryLight   = Color(0xFF25D366);
  static const accent         = Color(0xFF34B7F1);

  static const bgLight        = Color(0xFFECE5DD);
  static const bgWhite        = Color(0xFFFFFFFF);
  static const bgGray         = Color(0xFFF0F0F0);
  static const bgCard         = Color(0xFFFFFFFF);

  static const darkBg         = Color(0xFF0B141A);
  static const darkSurface    = Color(0xFF1F2C34);
  static const darkCard       = Color(0xFF1F2C34);
  static const darkBubbleSent = Color(0xFF056162);
  static const darkBubbleRcv  = Color(0xFF1F2C34);
  static const darkHeader     = Color(0xFF1F2C34);

  static const bubbleSent     = Color(0xFFDCF8C6);
  static const bubbleReceived = Color(0xFFFFFFFF);

  static const textPrimary    = Color(0xFF1A1A1A);
  static const textSecondary  = Color(0xFF667781);
  static const textLight      = Color(0xFF8696A0);
  static const textDark       = Color(0xFFE9EDEF);

  static const success        = Color(0xFF25D366);
  static const warning        = Color(0xFFFFC107);
  static const error          = Color(0xFFFF3B30);
  static const info           = Color(0xFF34B7F1);

  static const scoreHot       = Color(0xFFFF3B30);
  static const scoreWarm      = Color(0xFFFF9500);
  static const scoreCool      = Color(0xFF34B7F1);
  static const scoreCold      = Color(0xFF8696A0);

  static const p1             = Color(0xFFFF3B30);
  static const p2             = Color(0xFFFF9500);
  static const p3             = Color(0xFF34C759);
  static const p4             = Color(0xFF8696A0);

  static const stageNew       = Color(0xFF8696A0);
  static const stageEngaged   = Color(0xFF34B7F1);
  static const stageInterested= Color(0xFFFF9500);
  static const stagePayment   = Color(0xFF9C27B0);
  static const stageConverted = Color(0xFF25D366);
  static const stageLost      = Color(0xFFFF3B30);

  static Color scoreColor(int score) {
    if (score >= 76) return scoreHot;
    if (score >= 51) return scoreWarm;
    if (score >= 26) return scoreCool;
    return scoreCold;
  }

  static Color stageColor(String stage) {
    switch (stage) {
      case 'new': return stageNew;
      case 'engaged': return stageEngaged;
      case 'interested': return stageInterested;
      case 'payment': return stagePayment;
      case 'converted': return stageConverted;
      case 'lost': return stageLost;
      default: return stageNew;
    }
  }
}
