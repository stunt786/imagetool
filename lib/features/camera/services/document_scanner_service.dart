import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';

class DocumentScannerResult {
  const DocumentScannerResult({required this.files});

  final List<File> files;
}

class DocumentScannerService {
  static Future<DocumentScannerResult?> scanDocument() async {
    try {
      final scanner = DocumentScanner(
        options: DocumentScannerOptions(
          mode: ScannerMode.filter,
          isGalleryImport: true,
        ),
      );

      final result = await scanner.scanDocument();
      scanner.close();

      final imagePaths = result.images;
      if (imagePaths == null || imagePaths.isEmpty) return null;

      final files = imagePaths.map((path) => File(path)).toList();
      return DocumentScannerResult(files: files);
    } catch (e) {
      debugPrint('ML Kit scanner error: $e');
      return null;
    }
  }
}
