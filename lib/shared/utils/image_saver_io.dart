import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'image_saver_types.dart';

abstract final class AppSavePaths {
  static const String defaultDirectoryName = 'PixelTools';
  static const String _customPathKey = 'custom_save_path';

  static Future<Directory> getOutputDirectory() async {
    final prefs = await SharedPreferences.getInstance();
    final customPath = prefs.getString(_customPathKey);
    if (customPath != null && customPath.isNotEmpty) {
      final customDir = Directory(customPath);
      if (!await customDir.exists()) {
        await customDir.create(recursive: true);
      }
      return customDir;
    }

    if (Platform.isAndroid) {
      final picturesDir = Directory('/storage/emulated/0/Pictures/$defaultDirectoryName');
      if (!await picturesDir.exists()) {
        await picturesDir.create(recursive: true);
      }
      return picturesDir;
    }

    if (Platform.isIOS) {
      final baseDir = await getApplicationDocumentsDirectory();
      final outputDir = Directory(path.join(baseDir.path, defaultDirectoryName));
      if (!await outputDir.exists()) {
        await outputDir.create(recursive: true);
      }
      return outputDir;
    }

    final downloads = await getDownloadsDirectory();
    if (downloads != null) {
      final outputDir = Directory(path.join(downloads.path, defaultDirectoryName));
      if (!await outputDir.exists()) {
        await outputDir.create(recursive: true);
      }
      return outputDir;
    }

    final baseDir = await getApplicationDocumentsDirectory();
    final outputDir = Directory(path.join(baseDir.path, defaultDirectoryName));
    if (!await outputDir.exists()) {
      await outputDir.create(recursive: true);
    }
    return outputDir;
  }
}

Future<ImageSaveResult> saveImageBytesImpl(Uint8List bytes, {required String fileName}) async {
  final safeName = fileName.trim().isEmpty ? 'image.jpg' : fileName.trim();
  final prefixed = 'pixeltools_$safeName';
  final targetDir = await AppSavePaths.getOutputDirectory();

  final timestamp = DateTime.now().millisecondsSinceEpoch;
  final outName = _withSuffix(prefixed, '_$timestamp');
  final outFile = File('${targetDir.path}/$outName');
  await outFile.writeAsBytes(bytes, flush: true);
  return ImageSaveResult(fileName: outName, path: outFile.path);
}

Future<List<ImageSaveResult>> saveMultipleImagesImpl(
  List<({Uint8List bytes, String fileName})> items,
) async {
  final targetDir = await AppSavePaths.getOutputDirectory();
  final results = <ImageSaveResult>[];

  for (final item in items) {
    final safeName = item.fileName.trim().isEmpty ? 'image.jpg' : item.fileName.trim();
    final prefixed = 'pixeltools_$safeName';
    final timestamp = DateTime.now().millisecondsSinceEpoch + results.length;
    final outName = _withSuffix(prefixed, '_$timestamp');
    final outFile = File('${targetDir.path}/$outName');
    await outFile.writeAsBytes(item.bytes, flush: true);
    results.add(ImageSaveResult(fileName: outName, path: outFile.path));
  }

  return results;
}

String _withSuffix(String fileName, String suffix) {
  final dot = fileName.lastIndexOf('.');
  if (dot <= 0) return '$fileName$suffix.jpg';
  final base = fileName.substring(0, dot);
  final ext = fileName.substring(dot);
  return '$base$suffix$ext';
}
