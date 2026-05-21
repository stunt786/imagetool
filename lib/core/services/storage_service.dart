import 'dart:io';
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

class ImageSaveResult {
  const ImageSaveResult({
    required this.filePath,
    required this.fileName,
    required this.fileSize,
  });

  final String filePath;
  final String fileName;
  final int fileSize;
}

class StorageService {
  static const String _imageDirectoryName = 'PixelTools_Images';

  static Future<ImageSaveResult> saveImage({
    required Uint8List bytes,
    required String extension,
    String? customFileName,
  }) async {
    final directory = await getApplicationDocumentsDirectory();
    final imageDirectory = Directory(
      path.join(directory.path, _imageDirectoryName),
    );

    if (!await imageDirectory.exists()) {
      await imageDirectory.create(recursive: true);
    }

    final fileName = customFileName ?? _generateFileName(extension);
    final filePath = path.join(imageDirectory.path, fileName);
    final file = File(filePath);

    await file.writeAsBytes(bytes);
    final fileSize = await file.length();

    return ImageSaveResult(
      filePath: filePath,
      fileName: fileName,
      fileSize: fileSize,
    );
  }

  static Future<ImageSaveResult> saveMultipleImages({
    required List<({Uint8List bytes, String extension})> images,
  }) async {
    if (images.isEmpty) {
      throw ArgumentError('No images to save');
    }

    final directory = await getApplicationDocumentsDirectory();
    final imageDirectory = Directory(
      path.join(directory.path, _imageDirectoryName),
    );

    if (!await imageDirectory.exists()) {
      await imageDirectory.create(recursive: true);
    }

    final firstImage = images.first;
    final fileName = _generateFileName(firstImage.extension);
    final filePath = path.join(imageDirectory.path, fileName);
    final file = File(filePath);

    await file.writeAsBytes(firstImage.bytes);
    final fileSize = await file.length();

    return ImageSaveResult(
      filePath: filePath,
      fileName: fileName,
      fileSize: fileSize,
    );
  }

  static String _generateFileName(String extension) {
    final now = DateTime.now();
    final formatted = DateFormat('yyyyMMdd_HHmmss').format(now);
    return 'img_$formatted.$extension';
  }

  static String formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      final kb = bytes / 1024;
      return '${kb.toStringAsFixed(kb < 10 ? 1 : 0)} KB';
    }
    final mb = bytes / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} MB';
  }

  static String formatSizeComparison(int originalBytes, int newBytes) {
    final original = formatFileSize(originalBytes);
    final new_ = formatFileSize(newBytes);
    return '$original → $new_';
  }
}
