import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/services/public_storage.dart';
import 'image_saver_types.dart';

abstract final class AppSavePaths {
  static const String defaultDirectoryName = 'PixelTools';
  static const String _customPathKey = 'custom_save_path';

  static Future<Directory> getCacheDirectory() async {
    final temp = await getTemporaryDirectory();
    final cacheDir = Directory(path.join(temp.path, defaultDirectoryName));
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    return cacheDir;
  }

  /// App-private directory that is always writable without any permission.
  /// Android exports live here first and are then published to MediaStore (or
  /// the SAF folder chosen in Settings).
  static Future<Directory> getLocalOutputDirectory() async {
    final baseDir = await getApplicationDocumentsDirectory();
    final outputDir =
        Directory(path.join(baseDir.path, defaultDirectoryName));
    if (!await outputDir.exists()) {
      await outputDir.create(recursive: true);
    }
    return outputDir;
  }

  static Future<Directory> getOutputDirectory() async {
    // Android never writes raw paths into shared storage: shared destinations
    // are reached through MediaStore / SAF (see PublicStorage).
    if (Platform.isAndroid) {
      return getLocalOutputDirectory();
    }

    final prefs = await SharedPreferences.getInstance();
    final customPath = prefs.getString(_customPathKey);
    if (customPath != null && customPath.isNotEmpty) {
      final customDir = Directory(customPath);
      if (!await customDir.exists()) {
        await customDir.create(recursive: true);
      }
      return customDir;
    }

    if (Platform.isIOS) {
      return getLocalOutputDirectory();
    }

    final downloads = await getDownloadsDirectory();
    if (downloads != null) {
      final outputDir =
          Directory(path.join(downloads.path, defaultDirectoryName));
      if (!await outputDir.exists()) {
        await outputDir.create(recursive: true);
      }
      return outputDir;
    }

    return getLocalOutputDirectory();
  }
}

Future<ImageSaveResult> saveImageBytesImpl(
  Uint8List bytes, {
  required String fileName,
  String? replacePath,
}) async {
  // FilePicker supplies a writable path on native platforms. Respect an
  // explicit replacement request instead of silently creating a new export.
  // A fallback here made the UI claim an original had been replaced when it
  // had not, which is worse than a clear save error.
  if (replacePath != null && replacePath.isNotEmpty) {
    final original = File(replacePath);
    if (await original.exists()) {
      await original.writeAsBytes(bytes, flush: true);
      return ImageSaveResult(
          fileName: path.basename(original.path), path: original.path);
    }
    throw StateError('The original image is no longer available to replace.');
  }
  final safeName = fileName.trim().isEmpty ? 'image.jpg' : fileName.trim();
  final prefixed = 'pixeltools_$safeName';

  final timestamp = DateTime.now().millisecondsSinceEpoch;
  final outName = _withSuffix(prefixed, '_$timestamp');

  if (Platform.isAndroid) {
    // Keep a local copy for sharing/history, then publish the gallery entry
    // through MediaStore (or the SAF folder chosen in Settings).
    final targetDir = await AppSavePaths.getLocalOutputDirectory();
    final outFile = File('${targetDir.path}/$outName');
    await outFile.writeAsBytes(bytes, flush: true);
    try {
      await PublicStorage.publishBytes(
        bytes: bytes,
        fileName: outName,
        kind: PublicFileKind.image,
      );
    } catch (_) {
      await _deleteQuietly(outFile);
      rethrow;
    }
    return ImageSaveResult(fileName: outName, path: outFile.path);
  }

  final targetDir = await AppSavePaths.getOutputDirectory();
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
    final safeName =
        item.fileName.trim().isEmpty ? 'image.jpg' : item.fileName.trim();
    final prefixed = 'pixeltools_$safeName';
    final timestamp = DateTime.now().millisecondsSinceEpoch + results.length;
    final outName = _withSuffix(prefixed, '_$timestamp');

    if (Platform.isAndroid) {
      final localDir = await AppSavePaths.getLocalOutputDirectory();
      final outFile = File('${localDir.path}/$outName');
      await outFile.writeAsBytes(item.bytes, flush: true);
      try {
        await PublicStorage.publishBytes(
          bytes: item.bytes,
          fileName: outName,
          kind: PublicFileKind.image,
        );
      } catch (_) {
        await _deleteQuietly(outFile);
        rethrow;
      }
      results.add(ImageSaveResult(fileName: outName, path: outFile.path));
      continue;
    }

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

Future<void> _deleteQuietly(File file) async {
  try {
    if (await file.exists()) {
      await file.delete();
    }
  } catch (_) {
    // Best effort cleanup only.
  }
}
