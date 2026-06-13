import 'package:flutter/material.dart';

class AppColorTheme extends ThemeExtension<AppColorTheme> {
  const AppColorTheme({
    required this.canvas,
    required this.card,
    required this.chip,
    required this.banner,
    required this.primary,
    required this.text,
    required this.muted,
    required this.softMuted,
    required this.border,
    required this.strongBorder,
    required this.accent,
    required this.accentSoft,
    required this.success,
    required this.warning,
    required this.danger,
    required this.dangerSoft,
    required this.dangerBorder,
    required this.fontOnPrimary,
  });

  final Color canvas;
  final Color card;
  final Color chip;
  final Color banner;
  final Color primary;
  final Color text;
  final Color muted;
  final Color softMuted;
  final Color border;
  final Color strongBorder;
  final Color accent;
  final Color accentSoft;
  final Color success;
  final Color warning;
  final Color danger;
  final Color dangerSoft;
  final Color dangerBorder;
  final Color fontOnPrimary;

  static const light = AppColorTheme(
    canvas: Color(0xFFF7EFE0),
    card: Color(0xFFFBF5E6),
    chip: Color(0xFFF4ECD7),
    banner: Color(0xFFF7E4B0),
    primary: Color(0xFF5C4520),
    text: Color(0xFF2A2418),
    muted: Color(0xFF6B5E3F),
    softMuted: Color(0xFF9A8B68),
    border: Color(0xFFE2D5B3),
    strongBorder: Color(0xFFC9B98D),
    accent: Color(0xFFE5B33A),
    accentSoft: Color(0xFFFBEDC4),
    success: Color(0xFF5A8E3A),
    warning: Color(0xFFF59E0B),
    danger: Color(0xFFB9473D),
    dangerSoft: Color(0xFFFFECE8),
    dangerBorder: Color(0xFFF2C4BC),
    fontOnPrimary: Color(0xFFF7EFE0),
  );

  static const dark = AppColorTheme(
    canvas: Color(0xFF121212),
    card: Color(0xFF1E1E1E),
    chip: Color(0xFF2A2A2A),
    banner: Color(0xFF3D3520),
    primary: Color(0xFFE5B33A),
    text: Color(0xFFE8E0D4),
    muted: Color(0xFFA89B80),
    softMuted: Color(0xFF7A7060),
    border: Color(0xFF3A3530),
    strongBorder: Color(0xFF504838),
    accent: Color(0xFFE5B33A),
    accentSoft: Color(0xFF3D3520),
    success: Color(0xFF6EAF48),
    warning: Color(0xFFF59E0B),
    danger: Color(0xFFE06050),
    dangerSoft: Color(0xFF3D2020),
    dangerBorder: Color(0xFF5A3030),
    fontOnPrimary: Color(0xFF121212),
  );

  @override
  AppColorTheme copyWith({
    Color? canvas,
    Color? card,
    Color? chip,
    Color? banner,
    Color? primary,
    Color? text,
    Color? muted,
    Color? softMuted,
    Color? border,
    Color? strongBorder,
    Color? accent,
    Color? accentSoft,
    Color? success,
    Color? warning,
    Color? danger,
    Color? dangerSoft,
    Color? dangerBorder,
    Color? fontOnPrimary,
  }) {
    return AppColorTheme(
      canvas: canvas ?? this.canvas,
      card: card ?? this.card,
      chip: chip ?? this.chip,
      banner: banner ?? this.banner,
      primary: primary ?? this.primary,
      text: text ?? this.text,
      muted: muted ?? this.muted,
      softMuted: softMuted ?? this.softMuted,
      border: border ?? this.border,
      strongBorder: strongBorder ?? this.strongBorder,
      accent: accent ?? this.accent,
      accentSoft: accentSoft ?? this.accentSoft,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
      dangerSoft: dangerSoft ?? this.dangerSoft,
      dangerBorder: dangerBorder ?? this.dangerBorder,
      fontOnPrimary: fontOnPrimary ?? this.fontOnPrimary,
    );
  }

  @override
  AppColorTheme lerp(AppColorTheme? other, double t) {
    if (other == null) return this;
    return AppColorTheme(
      canvas: Color.lerp(canvas, other.canvas, t)!,
      card: Color.lerp(card, other.card, t)!,
      chip: Color.lerp(chip, other.chip, t)!,
      banner: Color.lerp(banner, other.banner, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      text: Color.lerp(text, other.text, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      softMuted: Color.lerp(softMuted, other.softMuted, t)!,
      border: Color.lerp(border, other.border, t)!,
      strongBorder: Color.lerp(strongBorder, other.strongBorder, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      dangerSoft: Color.lerp(dangerSoft, other.dangerSoft, t)!,
      dangerBorder: Color.lerp(dangerBorder, other.dangerBorder, t)!,
      fontOnPrimary: Color.lerp(fontOnPrimary, other.fontOnPrimary, t)!,
    );
  }
}

extension AppColors on BuildContext {
  AppColorTheme get colors => Theme.of(this).extension<AppColorTheme>()!;
}
