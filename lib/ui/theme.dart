// Copyright 2026 SSH Mate contributors
// SPDX-License-Identifier: GPL-3.0-only
import 'package:flutter/material.dart';

// Workbench design system. Semantic colors live in ColorScheme; these aliases
// are reserved for dark terminal accents and legacy decorative elements.
const canvas = Color(0xff111820);
const panel = Color(0xff1a2430);
const muted = Color(0xff9daebe);
const accent = Color(0xff8dbaff);

abstract final class MateSpace {
  static const double xs = 4, sm = 8, md = 16, lg = 24, xl = 32;
}

abstract final class MateMotion {
  static Duration duration(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : const Duration(milliseconds: 160);
}

ThemeData appTheme({bool light = false}) {
  final colors = ColorScheme.fromSeed(
    seedColor: const Color(0xff3977d5),
    brightness: light ? Brightness.light : Brightness.dark,
    primary: light ? const Color(0xff235ca5) : accent,
    onPrimary: light ? Colors.white : const Color(0xff102744),
    surface: light ? const Color(0xfff5f7fa) : canvas,
    onSurface: light ? const Color(0xff182635) : const Color(0xffe5edf5),
    onSurfaceVariant: light ? const Color(0xff536477) : muted,
    outlineVariant: light ? const Color(0xffd8e0e9) : const Color(0xff2d3c4c),
    surfaceContainerLow: light ? Colors.white : panel,
    surfaceContainerHighest: light
        ? const Color(0xffe7edf5)
        : const Color(0xff233142),
  );
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(10),
    borderSide: BorderSide(color: colors.outlineVariant),
  );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: colors,
    fontFamily: 'Segoe UI',
    scaffoldBackgroundColor: colors.surface,
  );
  return base.copyWith(
    textTheme: base.textTheme
        .copyWith(
          headlineMedium: TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.8,
            color: colors.onSurface,
          ),
          titleLarge: TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.w600,
            color: colors.onSurface,
          ),
          bodyMedium: TextStyle(
            fontSize: 14,
            height: 1.45,
            color: colors.onSurface,
          ),
          bodySmall: TextStyle(
            fontSize: 12,
            height: 1.5,
            color: colors.onSurfaceVariant,
          ),
        )
        .apply(fontFamily: 'Segoe UI'),
    dividerColor: colors.outlineVariant,
    dividerTheme: DividerThemeData(
      color: colors.outlineVariant,
      thickness: 1,
      space: 1,
    ),
    cardTheme: CardThemeData(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      color: colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colors.outlineVariant.withValues(alpha: .65)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colors.surfaceContainerLow,
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: BorderSide(color: colors.primary, width: 2),
      ),
      errorBorder: border.copyWith(borderSide: BorderSide(color: colors.error)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
      floatingLabelStyle: TextStyle(color: colors.primary),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(44, 44),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(44, 44),
        side: BorderSide(color: colors.outlineVariant),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(minimumSize: const Size(40, 40)),
    ),
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      showCloseIcon: true,
      backgroundColor: colors.inverseSurface,
      contentTextStyle: TextStyle(color: colors.onInverseSurface),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    chipTheme: ChipThemeData(
      side: BorderSide(color: colors.outlineVariant),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      selectedColor: colors.primaryContainer,
    ),
    tooltipTheme: const TooltipThemeData(
      waitDuration: Duration(milliseconds: 450),
    ),
  );
}
