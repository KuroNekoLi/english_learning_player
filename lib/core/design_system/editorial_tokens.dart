import 'package:material_ui/material_ui.dart';

abstract final class EditorialSpacing {
  static const xs = 4.0,
      sm = 8.0,
      md = 12.0,
      lg = 16.0,
      xl = 24.0,
      xxl = 32.0,
      xxxl = 48.0;
}

abstract final class EditorialRadius {
  static const small = 4.0, medium = 6.0, large = 8.0;
}

abstract final class EditorialSize {
  static const touch = 48.0, icon = 20.0, desktopPlay = 48.0, mobilePlay = 56.0;
  static const readerMin = 480.0, readerDefault = 900.0, readerMax = 1200.0;
  static const rail = 3.0, focus = 2.0, compact = 600.0, expanded = 900.0;
}

@immutable
final class EditorialColors extends ThemeExtension<EditorialColors> {
  const EditorialColors({
    required this.background,
    required this.surface,
    required this.textPrimary,
    required this.textSecondary,
    required this.primary,
    required this.onPrimary,
    required this.activeSubtitle,
    required this.divider,
    required this.controlOutline,
    required this.wordHighlight,
    required this.onWordHighlight,
    required this.error,
    required this.focus,
  });
  final Color background,
      surface,
      textPrimary,
      textSecondary,
      primary,
      onPrimary,
      activeSubtitle,
      divider,
      controlOutline,
      wordHighlight,
      onWordHighlight,
      error,
      focus;

  static const light = EditorialColors(
    background: Color(0xffF7F5EF),
    surface: Color(0xffFDFCF8),
    textPrimary: Color(0xff292D29),
    textSecondary: Color(0xff5E665E),
    primary: Color(0xff38634F),
    onPrimary: Color(0xffFFFFFF),
    activeSubtitle: Color(0xffE7EDE4),
    divider: Color(0xffDADDD4),
    controlOutline: Color(0xff778176),
    wordHighlight: Color(0xffE9DAA0),
    onWordHighlight: Color(0xff292D29),
    error: Color(0xff9C332D),
    focus: Color(0xff38634F),
  );
  static const dark = EditorialColors(
    background: Color(0xff1C211E),
    surface: Color(0xff242B26),
    textPrimary: Color(0xffEAEDE5),
    textSecondary: Color(0xffB1BDB1),
    primary: Color(0xff9BC5A8),
    onPrimary: Color(0xff17271D),
    activeSubtitle: Color(0xff293C31),
    divider: Color(0xff414D43),
    controlOutline: Color(0xff78877A),
    wordHighlight: Color(0xffD8C47E),
    onWordHighlight: Color(0xff292D29),
    error: Color(0xffFFB4A9),
    focus: Color(0xff9BC5A8),
  );
  static EditorialColors of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<EditorialColors>() ??
        (theme.brightness == Brightness.dark ? dark : light);
  }

  @override
  EditorialColors copyWith({
    Color? background,
    Color? surface,
    Color? textPrimary,
    Color? textSecondary,
    Color? primary,
    Color? onPrimary,
    Color? activeSubtitle,
    Color? divider,
    Color? controlOutline,
    Color? wordHighlight,
    Color? onWordHighlight,
    Color? error,
    Color? focus,
  }) => EditorialColors(
    background: background ?? this.background,
    surface: surface ?? this.surface,
    textPrimary: textPrimary ?? this.textPrimary,
    textSecondary: textSecondary ?? this.textSecondary,
    primary: primary ?? this.primary,
    onPrimary: onPrimary ?? this.onPrimary,
    activeSubtitle: activeSubtitle ?? this.activeSubtitle,
    divider: divider ?? this.divider,
    controlOutline: controlOutline ?? this.controlOutline,
    wordHighlight: wordHighlight ?? this.wordHighlight,
    onWordHighlight: onWordHighlight ?? this.onWordHighlight,
    error: error ?? this.error,
    focus: focus ?? this.focus,
  );
  @override
  EditorialColors lerp(covariant EditorialColors? other, double t) {
    if (other == null) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return EditorialColors(
      background: mix(background, other.background),
      surface: mix(surface, other.surface),
      textPrimary: mix(textPrimary, other.textPrimary),
      textSecondary: mix(textSecondary, other.textSecondary),
      primary: mix(primary, other.primary),
      onPrimary: mix(onPrimary, other.onPrimary),
      activeSubtitle: mix(activeSubtitle, other.activeSubtitle),
      divider: mix(divider, other.divider),
      controlOutline: mix(controlOutline, other.controlOutline),
      wordHighlight: mix(wordHighlight, other.wordHighlight),
      onWordHighlight: mix(onWordHighlight, other.onWordHighlight),
      error: mix(error, other.error),
      focus: mix(focus, other.focus),
    );
  }
}

double editorialContrast(Color a, Color b) {
  final x = a.computeLuminance(), y = b.computeLuminance();
  return x > y ? (x + .05) / (y + .05) : (y + .05) / (x + .05);
}

/// Returns the actual opaque composited color, retaining the requested
/// opacity when it satisfies the contrast floor.
Color readableTranslation(
  Color foreground,
  Color background,
  double requested, {
  double minimum = 4.5,
}) {
  Color blend(double alpha) =>
      Color.alphaBlend(foreground.withValues(alpha: alpha), background);
  final start = requested.clamp(0.0, 1.0).toDouble();
  if (editorialContrast(blend(start), background) >= minimum) {
    return blend(start);
  }
  if (editorialContrast(blend(1), background) < minimum) return blend(1);
  var low = start, high = 1.0;
  for (var i = 0; i < 20; i++) {
    final mid = (low + high) / 2;
    if (editorialContrast(blend(mid), background) >= minimum) {
      high = mid;
    } else {
      low = mid;
    }
  }
  return blend(high);
}
