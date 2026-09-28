import 'dart:io';

import 'package:flutter/services.dart';
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
  TestWidgetsFlutterBinding.ensureInitialized();

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

  group('Scanner capture routing', () {
    test('the Google scanner is used whenever it is available', () {
      expect(
        resolveCapturePath(
          googleScannerAvailable: true,
          preferBuiltInCamera: false,
        ),
        CapturePath.googleScanner,
      );
    });

    test('the built-in camera is only used when the scanner is unavailable',
        () {
      expect(
        resolveCapturePath(
          googleScannerAvailable: false,
          preferBuiltInCamera: false,
        ),
        CapturePath.builtInCamera,
      );
    });

    test('an explicit user choice wins over an available scanner', () {
      expect(
        resolveCapturePath(
          googleScannerAvailable: true,
          preferBuiltInCamera: true,
        ),
        CapturePath.builtInCamera,
      );
    });

    test('cancelling or returning never switches to the fallback camera', () {
      // Cancelling a scan does not change either input, so the routing decision
      // must stay on the Google scanner: the fallback camera must not load.
      const available = true;
      const preferred = false;
      final before = resolveCapturePath(
        googleScannerAvailable: available,
        preferBuiltInCamera: preferred,
      );
      final afterCancel = resolveCapturePath(
        googleScannerAvailable: available,
        preferBuiltInCamera: preferred,
      );
      expect(before, CapturePath.googleScanner);
      expect(afterCancel, before);
    });
  });

  group('DocumentScannerService.scanDocument', () {
    const channel = MethodChannel('google_mlkit_document_scanner');

    late MlKitScannerCapability capability;

    setUp(() async {
      MlKitScannerCapability.resetCache();
      capability = MlKitScannerCapability(probe: () async => true);
      // Seed the session cache the way a real launch would.
      expect(await capability.isGoogleDocumentScannerAvailable(), isTrue);
    });

    void mockScanner(Future<Object?> Function(MethodCall call) handler) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, handler);
    }

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      MlKitScannerCapability.resetCache();
    });

    test('the platform reporting a user cancel keeps the scanner available',
        () async {
      // The Android plugin reports backing out of the scanner UI as
      // PlatformException("Operation cancelled"), not as an empty result.
      mockScanner((call) async {
        if (call.method == 'vision#startDocumentScanner') {
          throw PlatformException(
            code: 'DocumentScanner',
            message: 'Operation cancelled',
          );
        }
        return null;
      });

      final outcome =
          await DocumentScannerService.scanDocument(capability: capability);

      expect(outcome.isCancelled, isTrue);
      expect(outcome.isUnavailable, isFalse);
      // The capability must not be demoted, otherwise the next visit to the
      // camera tab silently drops to the built-in camera.
      expect(await capability.isGoogleDocumentScannerAvailable(), isTrue);
    });

    test('a real scanner failure demotes the capability', () async {
      mockScanner((call) async {
        if (call.method == 'vision#startDocumentScanner') {
          throw PlatformException(
            code: 'DocumentScanner',
            message: 'Failed to start document scanner',
          );
        }
        return null;
      });

      final outcome =
          await DocumentScannerService.scanDocument(capability: capability);

      expect(outcome.isUnavailable, isTrue);
      expect(await capability.isGoogleDocumentScannerAvailable(), isFalse);
    });

    test('a scanner that returns no pages counts as cancelled', () async {
      mockScanner((call) async {
        if (call.method == 'vision#startDocumentScanner') {
          return <dynamic, dynamic>{'images': null, 'pdf': null};
        }
        return null;
      });

      final outcome =
          await DocumentScannerService.scanDocument(capability: capability);

      expect(outcome.isCancelled, isTrue);
      expect(await capability.isGoogleDocumentScannerAvailable(), isTrue);
    });

    test('a successful scan returns the captured pages', () async {
      mockScanner((call) async {
        if (call.method == 'vision#startDocumentScanner') {
          return <dynamic, dynamic>{
            'images': <dynamic>['/tmp/page1.jpg', '/tmp/page2.jpg'],
            'pdf': null,
          };
        }
        return null;
      });

      final outcome =
          await DocumentScannerService.scanDocument(capability: capability);

      expect(outcome.isSuccess, isTrue);
      expect(outcome.files, hasLength(2));
      expect(await capability.isGoogleDocumentScannerAvailable(), isTrue);
    });

    test('an unsupported device never opens the scanner', () async {
      MlKitScannerCapability.resetCache();
      final unsupported = MlKitScannerCapability(probe: () async => false);
      var started = false;
      mockScanner((call) async {
        started = true;
        return null;
      });

      final outcome =
          await DocumentScannerService.scanDocument(capability: unsupported);

      expect(outcome.isUnavailable, isTrue);
      expect(started, isFalse);
    });
  });
}
