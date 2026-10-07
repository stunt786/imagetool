import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixeltools/core/services/operation_store.dart';
import 'package:pixeltools/core/services/operation_store_provider.dart';
import 'package:pixeltools/core/services/thumbnail_service.dart';
import 'package:pixeltools/features/files/presentation/files_screen.dart';
import 'package:pixeltools/features/format_converter/presentation/format_converter_screen.dart';
import 'package:pixeltools/features/home/presentation/home_screen.dart';
import 'package:pixeltools/features/image_to_pdf/presentation/image_to_pdf_screen.dart';
import 'package:pixeltools/features/pdf_compress/presentation/pdf_compress_screen.dart';
import 'package:pixeltools/features/settings/presentation/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Device widths/heights from the responsive test matrix.
const Map<String, Size> _matrices = <String, Size>{
  '320x568 (small phone)': Size(320, 568),
  '360x640 (phone)': Size(360, 640),
  '412x915 (large phone)': Size(412, 915),
  '600x1024 (small tablet)': Size(600, 1024),
  '800x1280 (tablet)': Size(800, 1280),
  '640x360 (landscape)': Size(640, 360),
  '812x375 (landscape phone)': Size(812, 375),
  '960x540 (landscape)': Size(960, 540),
};

void main() {
  late Directory base;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    base = await Directory.systemTemp.createTemp('responsive_test_');
    // Never spawn isolates or touch path_provider during layout tests.
    ThumbnailService.debugOverride = (_) async => null;
  });

  tearDown(() async {
    ThumbnailService.debugOverride = null;
    try {
      await base.delete(recursive: true);
    } catch (_) {}
  });

  /// Pumps [screen] at [size] and fails only on a layout overflow, so genuine
  /// platform-plugin gaps in the test environment do not mask real problems.
  Future<void> expectNoOverflow(
    WidgetTester tester,
    Widget screen,
    Size size,
  ) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          operationStoreProvider.overrideWithValue(
            OperationStore(baseDirectoryProvider: () async => base),
          ),
        ],
        child: MaterialApp(home: screen),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));
    await tester.pump(const Duration(milliseconds: 320));

    final exception = tester.takeException();
    final overflowed = exception is FlutterError &&
        exception.message.toLowerCase().contains('overflow');
    expect(
      overflowed,
      isFalse,
      reason: 'Layout overflowed at $size: $exception',
    );
  }

  for (final entry in _matrices.entries) {
    final size = entry.value;
    final label = entry.key;

    testWidgets('HomeScreen fits $label', (tester) async {
      await expectNoOverflow(tester, const HomeScreen(), size);
    });

    testWidgets('FilesScreen fits $label', (tester) async {
      await expectNoOverflow(tester, const FilesScreen(), size);
    });

    testWidgets('FormatConverterScreen fits $label', (tester) async {
      await expectNoOverflow(tester, const FormatConverterScreen(), size);
    });

    testWidgets('ImageToPdfScreen fits $label', (tester) async {
      await expectNoOverflow(tester, const ImageToPdfScreen(), size);
    });

    testWidgets('PdfCompressScreen fits $label', (tester) async {
      await expectNoOverflow(tester, const PdfCompressScreen(), size);
    });

    testWidgets('SettingsScreen fits $label', (tester) async {
      await expectNoOverflow(tester, const SettingsScreen(), size);
    });
  }

  testWidgets('HomeScreen grid dynamically scales columns and keeps cards compact', (tester) async {
    final sizesAndExpectedColumns = <Size, int>{
      const Size(360, 640): 3,
      const Size(500, 800): 4,
      const Size(640, 360): 5,
      const Size(800, 1280): 5,
      const Size(1024, 768): 6,
    };

    for (final entry in sizesAndExpectedColumns.entries) {
      tester.view.physicalSize = entry.key;
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            operationStoreProvider.overrideWithValue(
              OperationStore(baseDirectoryProvider: () async => base),
            ),
          ],
          child: const MaterialApp(home: HomeScreen()),
        ),
      );
      await tester.pump();

      final gridViewFinder = find.byType(GridView);
      expect(gridViewFinder, findsOneWidget);

      final gridView = tester.widget<GridView>(gridViewFinder);
      final delegate = gridView.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;

      expect(
        delegate.crossAxisCount,
        entry.value,
        reason: 'Failed column count at size ${entry.key}',
      );
      expect(
        delegate.mainAxisExtent,
        isNotNull,
        reason: 'mainAxisExtent must be set to prevent oversized cards',
      );
      expect(
        delegate.mainAxisExtent!,
        lessThanOrEqualTo(105.0),
        reason: 'Card height should remain compact (< 105px)',
      );
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
