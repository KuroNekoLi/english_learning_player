import 'package:material_ui/material_ui.dart';

import 'editorial_tokens.dart';
import 'editorial_typography.dart';

abstract final class EditorialTheme {
  static final light = _make(Brightness.light, EditorialColors.light);
  static final dark = _make(Brightness.dark, EditorialColors.dark);
  static ThemeData _make(Brightness brightness, EditorialColors c) {
    final scheme = ColorScheme(
      brightness: brightness,
      primary: c.primary,
      onPrimary: c.onPrimary,
      primaryContainer: c.activeSubtitle,
      onPrimaryContainer: c.textPrimary,
      secondary: c.primary,
      onSecondary: c.onPrimary,
      secondaryContainer: c.activeSubtitle,
      onSecondaryContainer: c.textPrimary,
      tertiary: c.wordHighlight,
      onTertiary: c.onWordHighlight,
      tertiaryContainer: c.wordHighlight,
      onTertiaryContainer: c.onWordHighlight,
      error: c.error,
      onError: brightness == Brightness.light
          ? Colors.white
          : const Color(0xff32110D),
      surface: c.surface,
      onSurface: c.textPrimary,
      onSurfaceVariant: c.textSecondary,
      outline: c.controlOutline,
      outlineVariant: c.divider,
      surfaceContainerLowest: c.background,
      surfaceContainerLow: c.surface,
      surfaceContainer: c.surface,
      surfaceContainerHigh: c.activeSubtitle,
      surfaceContainerHighest: c.activeSubtitle,
      surfaceTint: Colors.transparent,
      inverseSurface: c.textPrimary,
      onInverseSurface: c.background,
    );
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: EditorialTypography.ui,
      fontFamilyFallback: EditorialTypography.fallback,
      scaffoldBackgroundColor: c.background,
      canvasColor: c.background,
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      extensions: [c],
    );
    final radius = BorderRadius.circular(EditorialRadius.medium);
    final shape = RoundedRectangleBorder(borderRadius: radius);
    TextStyle text(double size, FontWeight weight, double height) => TextStyle(
      fontSize: size,
      fontWeight: weight,
      height: height,
      fontFamily: EditorialTypography.ui,
      fontFamilyFallback: EditorialTypography.fallback,
      color: c.textPrimary,
    );
    Color? overlay(Set<WidgetState> states) {
      if (states.contains(WidgetState.focused)) {
        return c.primary.withValues(alpha: .16);
      }
      if (states.contains(WidgetState.pressed)) {
        return c.primary.withValues(alpha: .14);
      }
      if (states.contains(WidgetState.hovered)) {
        return c.primary.withValues(alpha: .08);
      }
      return null;
    }

    final focusSide = WidgetStateProperty.resolveWith<BorderSide?>(
      (s) => s.contains(WidgetState.focused)
          ? BorderSide(color: c.focus, width: 2)
          : null,
    );
    final filledFocus = WidgetStateProperty.resolveWith<BorderSide?>(
      (s) => s.contains(WidgetState.focused)
          ? BorderSide(color: c.onPrimary, width: 2)
          : null,
    );
    final common = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
      shape: WidgetStatePropertyAll(shape),
      overlayColor: WidgetStateProperty.resolveWith(overlay),
      side: focusSide,
      elevation: const WidgetStatePropertyAll(0),
    );
    return base.copyWith(
      textTheme: base.textTheme.copyWith(
        headlineMedium: text(32, FontWeight.w500, 1.2),
        headlineSmall: text(24, FontWeight.w500, 1.25),
        titleLarge: text(20, FontWeight.w500, 1.3),
        titleMedium: text(16, FontWeight.w500, 1.4),
        bodyLarge: text(16, FontWeight.w400, 1.5),
        bodyMedium: text(14, FontWeight.w400, 1.5),
        bodySmall: text(
          12,
          FontWeight.w400,
          1.4,
        ).copyWith(color: c.textSecondary),
        labelLarge: text(14, FontWeight.w500, 1.4),
        labelMedium: text(13, FontWeight.w500, 1.4),
        labelSmall: text(12, FontWeight.w400, 1.4),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: c.background,
        foregroundColor: c.textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: text(18, FontWeight.w500, 1.3),
      ),
      cardTheme: CardThemeData(
        color: c.surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        margin: const EdgeInsets.symmetric(vertical: 4),
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: c.divider),
        ),
      ),
      dividerTheme: DividerThemeData(color: c.divider, thickness: 1, space: 1),
      iconTheme: IconThemeData(color: c.textSecondary, size: 20),
      filledButtonTheme: FilledButtonThemeData(
        style: common.copyWith(
          side: filledFocus,
          backgroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.disabled) ? null : c.primary,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.disabled) ? null : c.onPrimary,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: common.copyWith(
          side: WidgetStateProperty.resolveWith(
            (s) => BorderSide(
              color: s.contains(WidgetState.focused)
                  ? c.focus
                  : c.controlOutline,
              width: s.contains(WidgetState.focused) ? 2 : 1,
            ),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(style: common),
      iconButtonTheme: IconButtonThemeData(
        style: common.copyWith(
          shape: const WidgetStatePropertyAll(CircleBorder()),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surface,
        border: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: c.controlOutline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: c.controlOutline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: c.focus, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: c.error),
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: c.primary,
        inactiveTrackColor: c.controlOutline,
        thumbColor: c.primary,
        trackHeight: 3,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        shape: shape,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        shape: shape,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: c.surface,
        surfaceTintColor: Colors.transparent,
        shape: shape,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: c.textSecondary,
        textColor: c.textPrimary,
        shape: shape,
        minTileHeight: 48,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
    );
  }
}
