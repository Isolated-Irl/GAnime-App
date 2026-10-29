// Central app theme tokens: Dark vs AMOLED is a real theme switch.
// Built per-settings in main.dart (GaColors.forMode) and read anywhere via
// GaColors.of(context), so AMOLED true-black applies to scaffolds, cards,
// sheets, dialogs, inputs and skeletons consistently — not just the scaffold.
import 'package:flutter/material.dart';

class GaColors extends ThemeExtension<GaColors> {
  /// Scaffold / page background.
  final Color surface;

  /// Cards, pills, chips, dropdowns, dialog & sheet backgrounds.
  final Color card;

  /// Text-field and inset fills.
  final Color field;

  const GaColors({
    required this.surface,
    required this.card,
    required this.field,
  });

  /// Dark (#0d0d0d family) vs AMOLED true-black.
  /// Matches the website: body.amoled-black only blacks the page background
  /// (--bg-amoled: #000000); cards stay #222222 so contrast is preserved.
  factory GaColors.forMode({required bool amoled}) => amoled
      ? const GaColors(
          surface: Colors.black,
          card: Color(0xFF222222),
          field: Color(0xFF1A1A1A),
        )
      : const GaColors(
          surface: Color(0xFF0D0D0D),
          card: Color(0xFF222222),
          field: Color(0xFF1A1A1A),
        );

  static GaColors of(BuildContext context) =>
      Theme.of(context).extension<GaColors>()!;

  @override
  GaColors copyWith({Color? surface, Color? card, Color? field}) => GaColors(
        surface: surface ?? this.surface,
        card: card ?? this.card,
        field: field ?? this.field,
      );

  @override
  GaColors lerp(ThemeExtension<GaColors>? other, double t) {
    if (other is! GaColors) return this;
    return GaColors(
      surface: Color.lerp(surface, other.surface, t)!,
      card: Color.lerp(card, other.card, t)!,
      field: Color.lerp(field, other.field, t)!,
    );
  }
}
