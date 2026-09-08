import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pixeltools/features/collage_builder/models/collage_state.dart';
import 'package:pixeltools/features/collage_builder/notifiers/collage_notifier.dart';
import 'package:pixeltools/features/collage_builder/widgets/collage_canvas.dart';

void main() {
  group('CollageState & CollageNotifier Component 2 Tests', () {
    test('Default CollageState contains caption offset, scale, and fontFamily', () {
      const state = CollageState(
        images: [],
        layout: CollageLayout(
          id: 'test',
          name: 'Test',
          slotCount: 1,
          slotRects: [Rect.fromLTRB(0, 0, 1, 1)],
        ),
        gap: 4.0,
        cornerRadius: 8.0,
        backgroundColor: Colors.white,
        canvasWidth: 1080,
        canvasHeight: 1080,
      );

      expect(state.captionNormalizedOffset, equals(const Offset(0.5, 0.85)));
      expect(state.captionScale, equals(1.0));
      expect(state.captionFontFamily, equals('Roboto'));
    });

    test('copyWith updates captionOffset, captionScale, and captionFontFamily', () {
      const state = CollageState(
        images: [],
        layout: CollageLayout(
          id: 'test',
          name: 'Test',
          slotCount: 1,
          slotRects: [Rect.fromLTRB(0, 0, 1, 1)],
        ),
        gap: 4.0,
        cornerRadius: 8.0,
        backgroundColor: Colors.white,
        canvasWidth: 1080,
        canvasHeight: 1080,
      );

      final updated = state.copyWith(
        captionNormalizedOffset: const Offset(0.2, 0.3),
        captionScale: 1.5,
        captionFontFamily: 'serif',
      );

      expect(updated.captionNormalizedOffset, equals(const Offset(0.2, 0.3)));
      expect(updated.captionScale, equals(1.5));
      expect(updated.captionFontFamily, equals('serif'));
    });

    testNotifier('CollageNotifier updates caption properties', (container) {
      final notifier = container.read(collageProvider.notifier);

      notifier.setCaptionNormalizedOffset(const Offset(0.4, 0.6));
      expect(container.read(collageProvider).captionNormalizedOffset, equals(const Offset(0.4, 0.6)));

      notifier.setCaptionScale(2.0);
      expect(container.read(collageProvider).captionScale, equals(2.0));

      notifier.setCaptionFontFamily('monospace');
      expect(container.read(collageProvider).captionFontFamily, equals('monospace'));
    });
  });

  group('CollageCanvas Caption Overlay Widget Tests', () {
    testWidgets('Renders caption text overlay when state.captionText is non-empty', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(collageProvider.notifier).setCaptionText('Test Overlay Caption');

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: CollageCanvas(),
            ),
          ),
        ),
      );

      expect(find.text('Test Overlay Caption'), findsOneWidget);
    });
  });
}

void testNotifier(String description, void Function(ProviderContainer container) body) {
  test(description, () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    body(container);
  });
}
