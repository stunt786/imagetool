import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'image_saver_types.dart';

Future<ImageSaveResult> saveImageBytesImpl(Uint8List bytes, {required String fileName}) async {
  final safeName = fileName.trim().isEmpty ? 'image.jpg' : fileName.trim();
  final targetDir = await _defaultSaveDirectory();

  final pixelToolsDir = Directory('${targetDir.path}/PixelTools');
  if (!await pixelToolsDir.exists()) {
    await pixelToolsDir.create(recursive: true);
  }

  final timestamp = DateTime.now().toIso8601String().replaceAll(':', '').replaceAll('.', '');
  final outName = _withSuffix(safeName, '_edited_$timestamp');
  final outFile = File('${pixelToolsDir.path}/$outName');
  await outFile.writeAsBytes(bytes, flush: true);
  return ImageSaveResult(fileName: outName, path: outFile.path);
}

Future<Directory> _defaultSaveDirectory() async {
  if (Platform.isAndroid) {
    final dir = await getExternalStorageDirectory();
    if (dir != null) return dir;
  }

  if (Platform.isIOS) {
    return getApplicationDocumentsDirectory();
  }

  final downloads = await getDownloadsDirectory();
  if (downloads != null) return downloads;

  return getApplicationDocumentsDirectory();
}

String _withSuffix(String fileName, String suffix) {
  final dot = fileName.lastIndexOf('.');
  if (dot <= 0) return '$fileName$suffix.jpg';
  final base = fileName.substring(0, dot);
  final ext = fileName.substring(dot);
  return '$base$suffix$ext';
}
