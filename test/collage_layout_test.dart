import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixeltools/features/collage_builder/notifiers/collage_notifier.dart';
import 'package:pixeltools/features/collage_builder/models/collage_palette.dart';
import 'package:pixeltools/features/collage_builder/models/collage_state.dart';

void main() {
  group('CollageLayout', () {
    test('exposes a 3x3 grid with nine tiling cells', () {
      final layout =
          CollageLayout.all.firstWhere((l) => l.id == 'grid_3x3');
      expect(layout.slotCount, 9);
      expect(layout.slotRects.length, 9);
      expect(
        layout.slotRects.first,
        const Rect.fromLTRB(0, 0, 1 / 3, 1 / 3),
      );
      expect(
        layout.slotRects.last,
        const Rect.fromLTRB(2 / 3, 2 / 3, 1, 1),
      );
    });

    test('grid cells cover the canvas without gaps or overlaps', () {
      final layout =
          CollageLayout.grid(rows: 3, columns: 3, id: 't', name: 'T');
      final area = layout.slotRects
          .fold<double>(0, (sum, rect) => sum + rect.width * rect.height);
      expect(area, closeTo(1.0, 1e-9));

      for (final rect in layout.slotRects) {
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.top, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(1));
        expect(rect.bottom, lessThanOrEqualTo(1));
        expect(rect.width, greaterThan(0));
        expect(rect.height, greaterThan(0));
      }
    });

    test('supports arbitrary grid shapes', () {
      final tall = CollageLayout.grid(rows: 4, columns: 2, id: 'x', name: 'X');
      expect(tall.slotCount, 8);
      expect(tall.slotRects.first.height, closeTo(0.25, 1e-9));
      expect(tall.slotRects.first.width, closeTo(0.5, 1e-9));
    });

    test('keeps every previously available layout and unique ids', () {
      final ids = CollageLayout.all.map((layout) => layout.id).toList();
      expect(
        ids,
        containsAll(<String>[
          'single',
          'horizontal_2',
          'vertical_2',
          'grid_2x2',
          'featured_top',
          'featured_left',
          'grid_2x3',
          'mosaic',
          't_layout',
          'grid_3x3',
        ]),
      );
      expect(ids.toSet().length, ids.length, reason: 'ids must be unique');
    });

    test('auto layout always returns a usable layout', () {
      for (var count = 1; count <= 12; count++) {
        final layout = CollageLayout.getLayoutForImageCount(count);
        expect(layout.slotCount, greaterThan(0));
        expect(layout.slotRects, isNotEmpty);
      }
    });
  });

  group('CollagePalette', () {
    test('offers a broad, duplicate-free palette', () {
      final colors = CollagePalette.all;
      expect(colors.length, greaterThanOrEqualTo(20));
      expect(colors.toSet().length, colors.length);
      expect(colors, contains(const Color(0xFFFFFFFF)));
      expect(colors, contains(const Color(0xFF000000)));
    });

    test('groups cover neutral, warm, cool and soft tones', () {
      final labels = CollagePalette.groups.map((group) => group.label).toList();
      expect(
        labels,
        containsAll(<String>['Neutral', 'Warm', 'Cool', 'Soft']),
      );
      for (final group in CollagePalette.groups) {
        expect(group.colors, isNotEmpty);
      }
    });

    test('isLight picks a readable foreground', () {
      expect(CollagePalette.isLight(const Color(0xFFFFFFFF)), isTrue);
      expect(CollagePalette.isLight(const Color(0xFFF7F7FA)), isTrue);
      expect(CollagePalette.isLight(const Color(0xFF000000)), isFalse);
      expect(CollagePalette.isLight(const Color(0xFF1E88E5)), isFalse);
    });
  });

  group('CollageTextLayer styling', () {
    test('defaults preserve the previous hard-coded look', () {
      const layer = CollageTextLayer(id: 'l1');
      expect(layer.bold, isTrue);
      expect(layer.italic, isFalse);
      expect(layer.opacity, 1.0);
      expect(layer.alignment, TextAlign.center);
    });

    test('copyWith updates styling without losing identity', () {
      const layer = CollageTextLayer(id: 'l1', text: 'Hello');
      final updated = layer.copyWith(
        bold: false,
        italic: true,
        opacity: 0.4,
        alignment: TextAlign.right,
      );
      expect(updated.id, 'l1');
      expect(updated.text, 'Hello');
      expect(updated.bold, isFalse);
      expect(updated.italic, isTrue);
      expect(updated.opacity, closeTo(0.4, 1e-9));
      expect(updated.alignment, TextAlign.right);
    });

    test('the notifier applies the new controls to a layer', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(collageProvider.notifier);

      notifier.addTextLayer();
      final id = container.read(collageProvider).textLayers.single.id;

      notifier.updateTextLayer(
        id,
        text: 'Caption',
        bold: false,
        italic: true,
        opacity: 0.5,
        alignment: TextAlign.left,
      );

      final layer = container.read(collageProvider).textLayers.single;
      expect(layer.text, 'Caption');
      expect(layer.bold, isFalse);
      expect(layer.italic, isTrue);
      expect(layer.opacity, closeTo(0.5, 1e-9));
      expect(layer.alignment, TextAlign.left);
      expect(layer.isEmpty, isFalse);
    });

    test('an empty layer is still treated as empty', () {
      const layer = CollageTextLayer(id: 'l1', text: '   ');
      expect(layer.isEmpty, isTrue);
    });
  });
}
