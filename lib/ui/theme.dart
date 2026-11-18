import 'package:material_ui/material_ui.dart';

abstract final class OnyxColors {
  static const background = Color(0xff111214);
  static const surface = Color(0xff1b1d20);
  static const elevated = Color(0xff25282d);
  static const border = Color(0xff34383f);
  static const text = Color(0xfff4eee4);
  static const muted = Color(0xffa6aaaf);
  static const accent = Color(0xffed8858);
  static const green = Color(0xff92cfa5);
  static const danger = Color(0xffff9d9d);
  static const slots = [
    Color(0xffb6a1dd),
    Color(0xffe29b70),
    Color(0xffed8858),
    Color(0xffd1be8e),
    Color(0xffb6ca8f),
    Color(0xff86bcae),
    Color(0xff8badd5),
    Color(0xffc2a0c6),
  ];
}

ThemeData onyxTheme() {
  final scheme =
      ColorScheme.fromSeed(
        seedColor: OnyxColors.accent,
        brightness: Brightness.dark,
      ).copyWith(
        primary: OnyxColors.accent,
        onPrimary: OnyxColors.background,
        surface: OnyxColors.surface,
        onSurface: OnyxColors.text,
        onSurfaceVariant: OnyxColors.muted,
        outline: OnyxColors.border,
        error: OnyxColors.danger,
      );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme);
  return base.copyWith(
    scaffoldBackgroundColor: OnyxColors.background,
    textTheme: base.textTheme.apply(
      bodyColor: OnyxColors.text,
      displayColor: OnyxColors.text,
    ),
    appBarTheme: const AppBarThemeData(
      backgroundColor: OnyxColors.background,
      foregroundColor: OnyxColors.text,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    cardTheme: CardThemeData(
      color: OnyxColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: OnyxColors.border),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        side: const BorderSide(color: OnyxColors.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
    inputDecorationTheme: InputDecorationThemeData(
      filled: true,
      fillColor: OnyxColors.elevated,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: OnyxColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: OnyxColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: OnyxColors.accent),
      ),
    ),
    sliderTheme: base.sliderTheme.copyWith(
      trackHeight: 4,
      activeTrackColor: OnyxColors.accent,
      inactiveTrackColor: OnyxColors.border,
      thumbColor: OnyxColors.accent,
      overlayColor: OnyxColors.accent.withValues(alpha: .12),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 70,
      backgroundColor: OnyxColors.background,
      surfaceTintColor: Colors.transparent,
      indicatorColor: OnyxColors.accent.withValues(alpha: .16),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 11,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w400,
          color: states.contains(WidgetState.selected)
              ? OnyxColors.accent
              : OnyxColors.muted,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          size: 22,
          color: states.contains(WidgetState.selected)
              ? OnyxColors.accent
              : OnyxColors.muted,
        ),
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: OnyxColors.background,
      indicatorColor: OnyxColors.accent.withValues(alpha: .16),
      selectedIconTheme: const IconThemeData(color: OnyxColors.accent),
      selectedLabelTextStyle: const TextStyle(color: OnyxColors.accent),
      unselectedLabelTextStyle: const TextStyle(color: OnyxColors.muted),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: OnyxColors.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: OnyxColors.surface,
      surfaceTintColor: Colors.transparent,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: OnyxColors.elevated,
      contentTextStyle: const TextStyle(color: OnyxColors.text),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    dividerTheme: const DividerThemeData(
      color: OnyxColors.border,
      thickness: 1,
      space: 24,
    ),
  );
}
