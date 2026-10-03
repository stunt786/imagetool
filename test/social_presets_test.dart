import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixeltools/features/image_resize/models/social_presets.dart';

void main() {
  group('SocialPreset catalogs', () {
    test('every profile preset is a positive 1:1 square', () {
      expect(SocialPresets.profilePresets, hasLength(3));
      for (final preset in SocialPresets.profilePresets) {
        expect(preset.width, greaterThan(0), reason: preset.name);
        expect(preset.height, greaterThan(0), reason: preset.name);
        expect(
          preset.width,
          preset.height,
          reason: '${preset.name} must be square',
        );
        expect(preset.description, '1:1 Square', reason: preset.name);
      }
    });

    test('banner presets keep their documented aspect ratios', () {
      final twitter = SocialPresets.findByName('Twitter Header');
      final linkedIn = SocialPresets.findByName('LinkedIn Banner');
      final youTube = SocialPresets.findByName('YouTube Banner');
      final facebookDesktop = SocialPresets.findByName('Facebook Cover (Desktop)');

      expect(twitter, isNotNull);
      expect(twitter!.width / twitter.height, closeTo(3.0, 0.001));
      expect(linkedIn, isNotNull);
      expect(linkedIn!.width / linkedIn.height, closeTo(4.0, 0.001));
      expect(youTube, isNotNull);
      expect(youTube!.width / youTube.height, closeTo(16 / 9, 0.001));
      expect(facebookDesktop, isNotNull);
      expect(facebookDesktop!.description, 'Desktop optimized');
      expect(facebookDesktop.width, greaterThan(facebookDesktop.height));
    });

    test('allPresets concatenates both groups without duplicate names', () {
      final all = SocialPresets.allPresets;
      expect(
        all,
        [...SocialPresets.profilePresets, ...SocialPresets.bannerPresets],
      );
      final names = all.map((p) => p.name).toList();
      expect(names.toSet(), hasLength(names.length));
      expect(all, hasLength(8));
    });

    test('findByName only matches the exact stored name', () {
      expect(SocialPresets.findByName('LinkedIn Profile'), isNotNull);
      expect(SocialPresets.findByName('linkedin profile'), isNull);
      expect(SocialPresets.findByName('Not A Real Preset'), isNull);
      expect(SocialPresets.findByName(''), isNull);
    });

    test('size exposes the pixel dimensions as a Flutter Size', () {
      const preset = SocialPreset(name: 'Custom', width: 640, height: 480);
      expect(preset.size, const Size(640, 480));
      expect(preset.description, isNull);
    });

    test('targetFileSizeKB covers 100 KB to 2 MB in ascending steps', () {
      expect(SocialPresets.targetFileSizeKB, [100, 200, 500, 1000, 2000]);
      final sorted = [...SocialPresets.targetFileSizeKB]..sort();
      expect(SocialPresets.targetFileSizeKB, sorted);
      expect(SocialPresets.targetFileSizeKB.first, 100);
      expect(SocialPresets.targetFileSizeKB.last, 2000);
    });
  });

  group('OutputImageFormat', () {
    test('labels and extensions line up with the encoder', () {
      expect(OutputImageFormat.jpg.label, 'JPG');
      expect(OutputImageFormat.jpg.extension, 'jpg');
      expect(OutputImageFormat.png.label, 'PNG');
      expect(OutputImageFormat.png.extension, 'png');
      expect(OutputImageFormat.webp.label, 'WebP');
      expect(OutputImageFormat.webp.extension, 'webp');
    });

    test('offers exactly the three encoders the pipeline implements', () {
      expect(OutputImageFormat.values, hasLength(3));
      final extensions = OutputImageFormat.values.map((f) => f.extension);
      expect(extensions, ['jpg', 'png', 'webp']);
    });
  });
}
