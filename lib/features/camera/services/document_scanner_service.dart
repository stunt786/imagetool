import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';

import 'scanner_capability_service.dart';

/// What happened when the ML Kit document scanner was opened.
enum DocumentScanStatus {
  /// At least one page was captured.
  success,

  /// The user backed out of the scanner UI. Not an error.
  cancelled,

  /// The scanner cannot run on this device (or failed to start).
  unavailable,
}

class DocumentScanOutcome {
  const DocumentScanOutcome({
    required this.status,
    this.files = const <File>[],
  });

  const DocumentScanOutcome.unavailable()
      : status = DocumentScanStatus.unavailable,
        files = const <File>[];

  const DocumentScanOutcome.cancelled()
      : status = DocumentScanStatus.cancelled,
        files = const <File>[];

  final DocumentScanStatus status;
  final List<File> files;

  bool get isSuccess =>
      status == DocumentScanStatus.success && files.isNotEmpty;

  bool get isCancelled => status == DocumentScanStatus.cancelled;

  bool get isUnavailable => status == DocumentScanStatus.unavailable;
}

/// Google ML Kit document scanner wrapper.
///
/// Distinguishes *cancelled* from *unavailable* so the caller never falls back
/// to the built-in camera just because the user changed their mind.
class DocumentScannerService {
  /// Runs one ML Kit document scan.
  ///
  /// [capability] is injectable for tests; production callers use the default.
  static Future<DocumentScanOutcome> scanDocument({
    ScannerCapabilityService? capability,
  }) async {
    // Never open a scanner the device cannot run.
    if (!await (capability ?? MlKitScannerCapability())
        .isGoogleDocumentScannerAvailable()) {
      return const DocumentScanOutcome.unavailable();
    }

    DocumentScanner? scanner;
    try {
      scanner = DocumentScanner(
        options: DocumentScannerOptions(
          mode: ScannerMode.full,
          isGalleryImport: false,
          pageLimit: 100,
        ),
      );

      final result = await scanner.scanDocument();
      final imagePaths = result.images;
      if (imagePaths == null || imagePaths.isEmpty) {
        // The scanner closed without returning pages: the user cancelled.
        return const DocumentScanOutcome.cancelled();
      }

      return DocumentScanOutcome(
        status: DocumentScanStatus.success,
        files: imagePaths.map((path) => File(path)).toList(),
      );
    } on PlatformException catch (e) {
      // The Android plugin reports the user backing out of the scanner UI as
      // a PlatformException("Operation cancelled"), never as an empty result.
      // It must not demote the scanner, otherwise backing out of one scan
      // permanently drops the app to the built-in camera.
      if (_isUserCancellation(e)) {
        debugPrint('ML Kit scanner cancelled by user');
        return const DocumentScanOutcome.cancelled();
      }
      // A real failure (missing Play services, scanner module unavailable,
      // permission problem): remember it so the next tap goes straight to the
      // built-in camera.
      debugPrint('ML Kit scanner error: $e');
      MlKitScannerCapability.markUnavailable();
      return const DocumentScanOutcome.unavailable();
    } catch (e) {
      debugPrint('ML Kit scanner error: $e');
      MlKitScannerCapability.markUnavailable();
      return const DocumentScanOutcome.unavailable();
    } finally {
      try {
        scanner?.close();
      } catch (_) {}
    }
  }

  /// True when [error] is the scanner UI being dismissed by the user rather
  /// than the scanner being unable to run.
  static bool _isUserCancellation(PlatformException error) {
    final text =
        '${error.code} ${error.message ?? ""} ${error.details ?? ""}'
            .toLowerCase();
    return text.contains('cancel') ||
        text.contains('user') ||
        text.contains('back') ||
        text.contains('dismiss') ||
        text.contains('closed') ||
        text.contains('abort');
  }

  /// True when the ML Kit scanner should be offered.
  static Future<bool> isAvailable({ScannerCapabilityService? capability}) =>
      (capability ?? MlKitScannerCapability())
          .isGoogleDocumentScannerAvailable();
}
