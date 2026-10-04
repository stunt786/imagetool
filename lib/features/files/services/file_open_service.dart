import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/utils/file_type_detector.dart';
import '../../../shared/models/edit_history_item.dart';
import '../../pdf_viewer/presentation/pdf_viewer_screen.dart';
import '../presentation/file_preview_screen.dart';

/// Single place that decides how a file is opened.
///
/// Keeping the type switch here means screens never scatter
/// "is this a PDF / image / something else" checks, and new file types only
/// need one new branch.
abstract final class FileOpenService {
  /// Opens [path] with the appropriate in-app viewer.
  ///
  /// [galleryItems] lets image previews keep the swipe-between-items behaviour
  /// of the Files list; when omitted a single-item preview is shown.
  static Future<void> open(
    BuildContext context, {
    required String path,
    String? name,
    List<EditHistoryItem>? galleryItems,
    int galleryIndex = 0,
    AppFileKind? kind,
  }) async {
    if (path.isEmpty) {
      _showMessage(context, 'This file is no longer available.');
      return;
    }

    final detected = FileTypeDetector.detect(path: path, name: name);
    final resolvedKind = kind ?? detected.kind;

    if (!File(path).existsSync()) {
      _showMessage(context, 'This file is no longer available.');
      return;
    }

    switch (resolvedKind) {
      case AppFileKind.pdf:
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => PdfViewerScreen(filePath: path, title: name),
          ),
        );
        break;
      case AppFileKind.image:
        final items = galleryItems != null && galleryItems.isNotEmpty
            ? galleryItems
            : <EditHistoryItem>[_singleImageItem(path, name)];
        final index = galleryItems != null && galleryItems.isNotEmpty
            ? galleryIndex.clamp(0, items.length - 1)
            : 0;
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) =>
                FilePreviewScreen(items: items, initialIndex: index),
          ),
        );
        break;
      case AppFileKind.other:
        _showMessage(
          context,
          'This file type cannot be opened in the app.',
        );
        break;
    }
  }

  static EditHistoryItem _singleImageItem(String path, String? name) {
    final fileName = (name == null || name.isEmpty)
        ? path.split(Platform.pathSeparator).last
        : name;
    return EditHistoryItem(
      fileName: fileName,
      toolUsed: 'Image',
      editedAt: DateTime.now(),
      filePath: path,
      thumbnailPath: path,
    );
  }

  static void _showMessage(BuildContext context, String message) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }
}
