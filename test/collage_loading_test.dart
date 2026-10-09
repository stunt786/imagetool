import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pixeltools/features/collage_builder/models/collage_state.dart';

void main() {
  group('CollageState loading functionality', () {
    test('default state has isLoading false and counts zero', () {
      final state = CollageState(
        images: List.generate(
          CollageLayout.all[0].slotCount,
          (i) => CollageImageSlot(index: i),
        ),
        layout: CollageLayout.all[0],
        gap: 4.0,
        cornerRadius: 8.0,
        backgroundColor: const Color(0xFFE8EAF6),
        canvasWidth: 1080,
        canvasHeight: 1080,
      );

      expect(state.isLoading, isFalse);
      expect(state.loadingMessage, isNull);
      expect(state.loadedCount, 0);
      expect(state.totalCount, 0);
    });

    test('copyWith updates loading properties correctly', () {
      final base = CollageState(
        images: List.generate(
          CollageLayout.all[0].slotCount,
          (i) => CollageImageSlot(index: i),
        ),
        layout: CollageLayout.all[0],
        gap: 4.0,
        cornerRadius: 8.0,
        backgroundColor: const Color(0xFFE8EAF6),
        canvasWidth: 1080,
        canvasHeight: 1080,
      );

      final loadingState = base.copyWith(
        isLoading: true,
        loadingMessage: 'Loading image 1 of 3...',
        loadedCount: 1,
        totalCount: 3,
      );

      expect(loadingState.isLoading, isTrue);
      expect(loadingState.loadingMessage, 'Loading image 1 of 3...');
      expect(loadingState.loadedCount, 1);
      expect(loadingState.totalCount, 3);

      final finishedState = loadingState.copyWith(
        isLoading: false,
        clearLoadingMessage: true,
      );

      expect(finishedState.isLoading, isFalse);
      expect(finishedState.loadingMessage, isNull);
    });
  });
}
