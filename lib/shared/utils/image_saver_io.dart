import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'image_saver_types.dart';

Future<ImageSaveResult> saveImageBytesImpl(Uint8List bytes, {required String fileName}) async {
  final safeName = fileName.trim().isEmpty ? 'image.jpg' : fileName.trim();
  final targetDir = await _pixelToolsDirectory();

  final timestamp = DateTime.now().millisecondsSinceEpoch;
  final outName = _withSuffix(safeName, '_$timestamp');
  final outFile = File('${targetDir.path}/$outName');
  await outFile.writeAsBytes(bytes, flush: true);
  return ImageSaveResult(fileName: outName, path: outFile.path);
}

Future<Directory> _pixelToolsDirectory() async {
  if (Platform.isAndroid) {
    final picturesDir = Directory('/storage/emulated/0/Pictures/PixelTools');
    if (!await picturesDir.exists()) {
      await picturesDir.create(recursive: true);
    }
    return picturesDir;
  }

  if (Platform.isIOS) {
    final baseDir = await getApplicationDocumentsDirectory();
    final pixelToolsDir = Directory(path.join(baseDir.path, 'PixelTools'));
    if (!await pixelToolsDir.exists()) {
      await pixelToolsDir.create(recursive: true);
    }
    return pixelToolsDir;
  }

  final downloads = await getDownloadsDirectory();
  if (downloads != null) {
    final pixelToolsDir = Directory(path.join(downloads.path, 'PixelTools'));
    if (!await pixelToolsDir.exists()) {
      await pixelToolsDir.create(recursive: true);
    }
    return pixelToolsDir;
  }

  final baseDir = await getApplicationDocumentsDirectory();
  final pixelToolsDir = Directory(path.join(baseDir.path, 'PixelTools'));
  if (!await pixelToolsDir.exists()) {
    await pixelToolsDir.create(recursive: true);
  }
  return pixelToolsDir;
}

String _withSuffix(String fileName, String suffix) {
  final dot = fileName.lastIndexOf('.');
  if (dot <= 0) return '$fileName$suffix.jpg';
  final base = fileName.substring(0, dot);
  final ext = fileName.substring(dot);
  return '$base$suffix$ext';
}
