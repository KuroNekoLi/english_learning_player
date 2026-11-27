import 'package:material_ui/material_ui.dart';

abstract final class EditorialTypography {
  static const ui = 'Inter';
  static const reading = 'Source Serif 4';
  static const chinese = 'Noto Sans TC';
  static const fallback = [chinese];
  static TextStyle english(
    BuildContext context, {
    double size = 19,
    double height = 1.45,
  }) => (Theme.of(context).textTheme.bodyLarge ?? const TextStyle()).copyWith(
    fontFamily: reading,
    fontFamilyFallback: fallback,
    fontSize: size,
    height: height,
    fontWeight: FontWeight.w400,
  );
  static TextStyle translation(
    BuildContext context, {
    double size = 15,
    double height = 1.45,
    Color? color,
  }) => (Theme.of(context).textTheme.bodyMedium ?? const TextStyle()).copyWith(
    fontFamily: chinese,
    fontFamilyFallback: const [ui],
    fontSize: size,
    height: height,
    color: color,
    fontWeight: FontWeight.w400,
  );
}
