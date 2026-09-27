import 'dart:io';

import 'package:flutter/foundation.dart';
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
  static Future<DocumentScanOutcome> scanDocument() async {
    // Never open a scanner the device cannot run.
    if (!await isAvailable()) {
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
    } catch (e) {
      // A real failure (missing Play services, scanner module unavailable,
      // permission problem): remember it so the next tap goes straight to the
      // built-in camera.
      debugPrint('ML Kit scanner error: $e');
      MlKitScannerCapability.markUnavailable();
      return const DocumentScanOutcome.unavailable();
    } finally {
      try {
        scanner?.close();
      } catch (_) {}
    }
  }

  /// True when the ML Kit scanner should be offered.
  static Future<bool> isAvailable() =>
      MlKitScannerCapability().isGoogleDocumentScannerAvailable();
}
