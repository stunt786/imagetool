import 'package:flutter/material.dart';

/// A labelled group of background colours shown in the collage colour sheet.
@immutable
class CollageColorGroup {
  const CollageColorGroup(this.label, this.colors);

  final String label;
  final List<Color> colors;
}

/// Curated solid background palette for collages.
///
/// Deliberately dependency-free: a small, well-chosen set of solid colours is
/// easier to use on a phone than a full colour picker, and covers the tones
/// people actually want behind photos (paper neutrals, warm accents, cool
/// accents and the soft pastels the app already shipped).
abstract final class CollagePalette {
  static const List<CollageColorGroup> groups = <CollageColorGroup>[
    CollageColorGroup('Neutral', <Color>[
      Color(0xFFFFFFFF),
      Color(0xFFF7F7FA),
      Color(0xFFE6E6EB),
      Color(0xFFC7C9D1),
      Color(0xFF8A8D99),
      Color(0xFF4A4D57),
      Color(0xFF1B1C20),
      Color(0xFF000000),
    ]),
    CollageColorGroup('Warm', <Color>[
      Color(0xFFE53935),
      Color(0xFFFB8C00),
      Color(0xFFFDD835),
      Color(0xFFD81B60),
      Color(0xFFFF7043),
      Color(0xFF8D6E63),
    ]),
    CollageColorGroup('Cool', <Color>[
      Color(0xFF43A047),
      Color(0xFF00897B),
      Color(0xFF00ACC1),
      Color(0xFF1E88E5),
      Color(0xFF3949AB),
      Color(0xFF8E24AA),
    ]),
    CollageColorGroup('Soft', <Color>[
      Color(0xFFE8EAF6),
      Color(0xFFFFF3E0),
      Color(0xFFE8F5E9),
      Color(0xFFE3F2FD),
      Color(0xFFFCE4EC),
      Color(0xFFF3F5F7),
    ]),
  ];

  /// Flat list of every available colour.
  static List<Color> get all => <Color>[
        for (final group in groups) ...group.colors,
      ];

  /// True when [color] is light enough to need dark foreground content.
  static bool isLight(Color color) => color.computeLuminance() > 0.6;
}
