import 'package:flutter/material.dart';

/// Shared color tokens for the native UI. Matches the warm cream/amber palette
/// defined in the Pencil design (`native/design/native.pen`).
abstract final class AppPalette {
  static const canvas = Color(0xFFF7EFE0);
  static const card = Color(0xFFFBF5E6);
  static const chip = Color(0xFFF4ECD7);
  static const banner = Color(0xFFF7E4B0);

  static const primary = Color(0xFF5C4520);
  static const text = Color(0xFF2A2418);
  static const muted = Color(0xFF6B5E3F);
  static const softMuted = Color(0xFF9A8B68);

  static const border = Color(0xFFE2D5B3);
  static const strongBorder = Color(0xFFC9B98D);

  static const accent = Color(0xFFE5B33A);
  static const accentSoft = Color(0xFFFBEDC4);

  static const success = Color(0xFF5A8E3A);
  static const warning = Color(0xFFF59E0B);
  static const danger = Color(0xFFB9473D);
  static const dangerSoft = Color(0xFFFFECE8);
  static const dangerBorder = Color(0xFFF2C4BC);

  static const fontOnPrimary = Color(0xFFF7EFE0);
}
