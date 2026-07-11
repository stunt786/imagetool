import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class BatchStorageService {
  static const _batchRoot = 'temp_scans';

  static Future<Directory> get _batchRootDir async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(appDir.path, _batchRoot));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static Future<Directory> createBatchDirectory(String batchId) async {
    final root = await _batchRootDir;
    final batchDir = Directory(p.join(root.path, batchId));
    if (!await batchDir.exists()) {
      await batchDir.create(recursive: true);
    }
    return batchDir;
  }

  static Future<String> savePage({
    required String batchId,
    required int pageIndex,
    required Uint8List imageBytes,
  }) async {
    final batchDir = await createBatchDirectory(batchId);
    final fileName = 'page_$pageIndex.jpg';
    final filePath = p.join(batchDir.path, fileName);
    final file = File(filePath);
    await file.writeAsBytes(imageBytes);
    return filePath;
  }

  static Future<Uint8List?> loadPage(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        return file.readAsBytes();
      }
    } catch (_) {}
    return null;
  }

  static Future<List<String>> loadBatchPagePaths(String batchId) async {
    final root = await _batchRootDir;
    final batchDir = Directory(p.join(root.path, batchId));
    if (!await batchDir.exists()) return [];

    final files = await batchDir.list().toList();
    files.sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));
    return files
        .where((f) => f is File && f.path.endsWith('.jpg'))
        .map((f) => f.path)
        .toList();
  }

  static Future<void> deleteBatch(String batchId) async {
    final root = await _batchRootDir;
    final batchDir = Directory(p.join(root.path, batchId));
    if (await batchDir.exists()) {
      await batchDir.delete(recursive: true);
    }
  }

  static Future<void> deletePageFile(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  static Future<void> cleanOrphanedBatches(
    Set<String> activeBatchIds,
  ) async {
    final root = await _batchRootDir;
    final dirs = await root.list().toList();
    for (final dir in dirs) {
      if (dir is Directory) {
        final batchId = p.basename(dir.path);
        if (!activeBatchIds.contains(batchId)) {
          // Older than 24 hours
          final stat = await dir.stat();
          final age = DateTime.now().difference(stat.modified);
          if (age.inHours > 24) {
            await dir.delete(recursive: true);
          }
        }
      }
    }
  }
}
