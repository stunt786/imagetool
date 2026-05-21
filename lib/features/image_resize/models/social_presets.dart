import 'package:flutter/material.dart';

class SocialPreset {
  const SocialPreset({
    required this.name,
    required this.width,
    required this.height,
    this.description,
  });

  final String name;
  final int width;
  final int height;
  final String? description;

  Size get size => Size(width.toDouble(), height.toDouble());
}

class SocialPresets {
  static const List<SocialPreset> profilePresets = <SocialPreset>[
    SocialPreset(
      name: 'Instagram/FB/Twitter Profile',
      width: 1080,
      height: 1080,
      description: '1:1 Square',
    ),
    SocialPreset(
      name: 'LinkedIn Profile',
      width: 400,
      height: 400,
      description: '1:1 Square',
    ),
    SocialPreset(
      name: 'YouTube Profile',
      width: 800,
      height: 800,
      description: '1:1 Square',
    ),
  ];

  static const List<SocialPreset> bannerPresets = <SocialPreset>[
    SocialPreset(
      name: 'Twitter Header',
      width: 1500,
      height: 500,
      description: '3:1 Aspect Ratio',
    ),
    SocialPreset(
      name: 'Facebook Cover (Desktop)',
      width: 820,
      height: 312,
      description: 'Desktop optimized',
    ),
    SocialPreset(
      name: 'Facebook Cover (Mobile)',
      width: 640,
      height: 360,
      description: 'Mobile optimized',
    ),
    SocialPreset(
      name: 'LinkedIn Banner',
      width: 1584,
      height: 396,
      description: '4:1 Aspect Ratio',
    ),
    SocialPreset(
      name: 'YouTube Banner',
      width: 2560,
      height: 1440,
      description: '16:9 - Safe area centering',
    ),
  ];

  static const List<int> targetFileSizeKB = <int>[100, 200, 500, 1000, 2000];

  static List<SocialPreset> get allPresets => <SocialPreset>[
        ...profilePresets,
        ...bannerPresets,
      ];

  static SocialPreset? findByName(String name) {
    try {
      return allPresets.firstWhere((preset) => preset.name == name);
    } catch (_) {
      return null;
    }
  }
}

enum OutputImageFormat {
  jpg('JPG', 'jpg'),
  png('PNG', 'png'),
  webp('WebP', 'webp');

  const OutputImageFormat(this.label, this.extension);

  final String label;
  final String extension;
}
