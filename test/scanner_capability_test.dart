import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixeltools/features/camera/services/document_scanner_service.dart';
import 'package:pixeltools/features/camera/services/scanner_capability_service.dart';

class _FakeCapability implements ScannerCapabilityService {
  _FakeCapability(this._value);

  final bool _value;
  int calls = 0;

  @override
  Future<bool> isGoogleDocumentScannerAvailable() async {
    calls++;
    return _value;
  }
}

void main() {
  setUp(MlKitScannerCapability.resetCache);
  tearDown(MlKitScannerCapability.resetCache);

  group('MlKitScannerCapability', () {
    test('probes once and caches the result for the session', () async {
      var calls = 0;
      final service = MlKitScannerCapability(
        probe: () async {
          calls++;
          return true;
        },
      );

      expect(await service.isGoogleDocumentScannerAvailable(), isTrue);
      expect(await service.isGoogleDocumentScannerAvailable(), isTrue);
      expect(calls, 1);
    });

    test('a failed launch demotes the capability', () async {
      final service = MlKitScannerCapability(probe: () async => true);
      expect(await service.isGoogleDocumentScannerAvailable(), isTrue);

      MlKitScannerCapability.markUnavailable();
      expect(await service.isGoogleDocumentScannerAvailable(), isFalse);
    });

    test('a throwing probe reports unavailable instead of crashing', () async {
      final service = MlKitScannerCapability(
        probe: () async => throw StateError('play services missing'),
      );
      expect(await service.isGoogleDocumentScannerAvailable(), isFalse);
    });

    test('non-Android platforms never report the ML scanner', () async {
      if (Platform.isAndroid) return;
      MlKitScannerCapability.resetCache();
      expect(
        await MlKitScannerCapability().isGoogleDocumentScannerAvailable(),
        isFalse,
      );
    });

    test('can be overridden through the provider', () async {
      final fake = _FakeCapability(false);
      final container = ProviderContainer(
        overrides: [scannerCapabilityProvider.overrideWithValue(fake)],
      );
      addTearDown(container.dispose);

      expect(
        await container
            .read(scannerCapabilityProvider)
            .isGoogleDocumentScannerAvailable(),
        isFalse,
      );
      expect(fake.calls, 1);
    });
  });

  group('DocumentScanOutcome', () {
    test('distinguishes cancelled from unavailable', () {
      const cancelled = DocumentScanOutcome.cancelled();
      const unavailable = DocumentScanOutcome.unavailable();

      expect(cancelled.isCancelled, isTrue);
      expect(cancelled.isUnavailable, isFalse);
      expect(cancelled.isSuccess, isFalse);

      expect(unavailable.isUnavailable, isTrue);
      expect(unavailable.isCancelled, isFalse);
      expect(unavailable.files, isEmpty);
    });

    test('success requires at least one page', () {
      const empty = DocumentScanOutcome(
        status: DocumentScanStatus.success,
      );
      expect(empty.isSuccess, isFalse);

      final withPage = DocumentScanOutcome(
        status: DocumentScanStatus.success,
        files: [File('/tmp/page.jpg')],
      );
      expect(withPage.isSuccess, isTrue);
    });
  });
}
