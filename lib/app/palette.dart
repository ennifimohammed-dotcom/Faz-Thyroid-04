import 'package:flutter/material.dart';

/// Couleurs « donnees » (courbes, types de dose) : identiques quel que soit le theme.
const Color kRose = Color(0xFFC25B85);
const Color kRoseDeep = Color(0xFF9E3D66);
const Color kLavender = Color(0xFF9B7EC8);
const Color kBlush = Color(0xFFFFF4F8);
const Color kPeach = Color(0xFFE59478);
const Color kMint = Color(0xFF3FA67F);
const Color kSky = Color(0xFF7B8CDE);

const LinearGradient kHeaderGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFFE58AAE), Color(0xFF9B7EC8)],
);

/// Theme de couleur de l'application (4 au choix).
class AppPalette {
  const AppPalette({
    required this.id,
    required this.nameKey,
    required this.seed,
    required this.secondary,
    required this.deep,
    required this.blush,
    required this.gradientStart,
    required this.gradientEnd,
  });

  final String id, nameKey;
  final Color seed, secondary, deep, blush, gradientStart, gradientEnd;

  LinearGradient get gradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [gradientStart, gradientEnd],
      );
}

const List<AppPalette> kPalettes = [
  AppPalette(
    id: 'rose',
    nameKey: 'pal_rose',
    seed: Color(0xFFC25B85),
    secondary: Color(0xFF9B7EC8),
    deep: Color(0xFF9E3D66),
    blush: Color(0xFFFFF4F8),
    gradientStart: Color(0xFFE58AAE),
    gradientEnd: Color(0xFF9B7EC8),
  ),
  AppPalette(
    id: 'lavender',
    nameKey: 'pal_lavender',
    seed: Color(0xFF8E6BBF),
    secondary: Color(0xFFE58AAE),
    deep: Color(0xFF5E3F8F),
    blush: Color(0xFFF8F4FF),
    gradientStart: Color(0xFFB39DDB),
    gradientEnd: Color(0xFF7E57C2),
  ),
  AppPalette(
    id: 'mint',
    nameKey: 'pal_mint',
    seed: Color(0xFF2FA39A),
    secondary: Color(0xFF7FC8A9),
    deep: Color(0xFF1B6F69),
    blush: Color(0xFFF1FBF9),
    gradientStart: Color(0xFF6FD3C5),
    gradientEnd: Color(0xFF3B8FB5),
  ),
  AppPalette(
    id: 'peach',
    nameKey: 'pal_peach',
    seed: Color(0xFFE07A5F),
    secondary: Color(0xFFF2B880),
    deep: Color(0xFFA94F38),
    blush: Color(0xFFFFF6F1),
    gradientStart: Color(0xFFF4A58A),
    gradientEnd: Color(0xFFD9778F),
  ),
];

AppPalette paletteById(String? id) =>
    kPalettes.firstWhere((p) => p.id == id, orElse: () => kPalettes.first);

/// Couleurs de marque ajoutees au ThemeData (suivent le theme choisi).
class BrandColors extends ThemeExtension<BrandColors> {
  const BrandColors(
      {required this.deep, required this.blush, required this.gradient});
  final Color deep, blush;
  final LinearGradient gradient;

  @override
  BrandColors copyWith({Color? deep, Color? blush, LinearGradient? gradient}) =>
      BrandColors(
        deep: deep ?? this.deep,
        blush: blush ?? this.blush,
        gradient: gradient ?? this.gradient,
      );

  @override
  BrandColors lerp(ThemeExtension<BrandColors>? other, double t) {
    if (other is! BrandColors) return this;
    return BrandColors(
      deep: Color.lerp(deep, other.deep, t) ?? deep,
      blush: Color.lerp(blush, other.blush, t) ?? blush,
      gradient: LinearGradient.lerp(gradient, other.gradient, t) ?? gradient,
    );
  }
}

extension BrandContext on BuildContext {
  BrandColors get _brand =>
      Theme.of(this).extension<BrandColors>() ??
      const BrandColors(deep: kRoseDeep, blush: kBlush, gradient: kHeaderGradient);

  /// Couleur principale du theme choisi.
  Color get brand => Theme.of(this).colorScheme.primary;
  Color get brandDeep => _brand.deep;
  LinearGradient get brandGradient => _brand.gradient;
}
