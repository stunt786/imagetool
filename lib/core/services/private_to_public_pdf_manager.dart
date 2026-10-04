import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../../shared/models/picked_file.dart';
import '../utils/file_type_detector.dart';
import 'public_storage.dart';

/// Orchestrates the two-phase "Sandbox-to-Public" PDF pipeline:
///
/// 1. **Sandbox Phase** — copies picked files into the app's isolated temp
///    cache directory (`/data/.../cache`) where all processing occurs.
/// 2. **Export Phase** — uses the Storage Access Framework (via
///    `FilePicker.saveFile()` / `FilePicker.getDirectoryPath()`) to write the
///    final bytes to a user-selected public folder (Downloads, Documents, etc.)
///    bypassing Scoped Storage restrictions.
///
/// Strict `try-catch-finally` guarantees that sandbox files are deleted even
/// when processing or export fails, keeping the app's disk footprint at 0 MB
/// after each session.
class PrivateToPublicPdfManager {
  List<String> _sandboxFiles = [];
  Directory? _sandboxDir;

  /// Returns the unique sandbox directory for this session.
  Future<Directory> _getSandboxDir() async {
    if (_sandboxDir != null) return _sandboxDir!;
    final temp = await getTemporaryDirectory();
    _sandboxDir = Directory(
      path.join(
        temp.path,
        'pixeltools_sandbox_${DateTime.now().millisecondsSinceEpoch}',
      ),
    );
    await _sandboxDir!.create(recursive: true);
    return _sandboxDir!;
  }

  /// Copies a source file into the sandbox.
  /// Returns the sandbox path.
  Future<String> copyToSandbox(String sourcePath) async {
    final dir = await _getSandboxDir();
    final baseName = path.basename(sourcePath).replaceAll(RegExp(r'[\/\\:\*\?"<>|]'), '_');
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final destPath = path.join(dir.path, '${timestamp}_$baseName');
    await File(sourcePath).copy(destPath);
    _sandboxFiles.add(destPath);
    return destPath;
  }

  /// Writes raw bytes into the sandbox as a new file.
  /// Returns the sandbox path.
  Future<String> writeToSandbox(Uint8List bytes, String fileName) async {
    final dir = await _getSandboxDir();
    final safeName = path.basename(fileName).replaceAll(RegExp(r'[\/\\:\*\?"<>|]'), '_');
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final destPath = path.join(dir.path, '${timestamp}_$safeName');
    await File(destPath).writeAsBytes(bytes, flush: true);
    _sandboxFiles.add(destPath);
    return destPath;
  }

  /// Imports a picked file into the sandbox, preferring a filesystem copy
  /// (constant memory) over buffering bytes. Throws a [StateError] with an
  /// actionable message when neither a readable path nor bytes exist, instead
  /// of surfacing a raw PathNotFound/FileSystemException.
  Future<String> importPickedFile(PickedFile file) async {
    if (file.sizeBytes > FileTypeDetector.maxPdfSizeBytes) {
      throw StateError(
        'File "${file.name}" exceeds the 20 MB size limit.',
      );
    }

    final sourcePath = file.path;
    if (sourcePath != null && sourcePath.isNotEmpty) {
      try {
        final srcFile = File(sourcePath);
        if (await srcFile.exists()) {
          final len = await srcFile.length();
          if (len > FileTypeDetector.maxPdfSizeBytes) {
            throw StateError(
              'File "${file.name}" exceeds the 20 MB size limit.',
            );
          }
          return copyToSandbox(sourcePath);
        }
      } catch (e) {
        if (e is StateError) rethrow;
        // Fall through to the bytes path below.
      }
      if (file.bytes == null) {
        throw StateError(
          'Could not read "${file.name}": the source file is no longer '
          'available. Please pick the file again.',
        );
      }
    }
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      throw StateError(
        'Could not read "${file.name}". Please pick the file again.',
      );
    }
    if (bytes.length > FileTypeDetector.maxPdfSizeBytes) {
      throw StateError(
        'File "${file.name}" exceeds the 20 MB size limit.',
      );
    }
    return writeToSandbox(bytes, file.name);
  }

  /// Exports a single sandbox file to a user-selected public location via SAF.
  /// Opens the system "Save" dialog. Returns the public path or null if
  /// the user cancelled.
  Future<String?> exportSingleFile({
    required String sandboxPath,
    String? suggestedName,
  }) async {
    final file = File(sandboxPath);
    if (!await file.exists()) return null;

    final bytes = await file.readAsBytes();
    final name = path.basename(suggestedName ?? path.basename(sandboxPath)).replaceAll(RegExp(r'[\/\\:\*\?"<>|]'), '_');

    final outputPath = await FilePicker.saveFile(
      dialogTitle: name.toLowerCase().endsWith('.pdf') ? 'Save PDF' : 'Save File',
      fileName: name,
      bytes: bytes,
    );

    return outputPath;
  }

  /// Exports multiple sandbox files to a user-selected public directory via SAF.
  /// Opens the system directory picker. Returns the list of public paths
  /// (empty if the user cancelled).
  ///
  /// On Android this writes through the persisted tree grant (DocumentFile),
  /// not raw `File` copies — scoped storage rejects those without
  /// `MANAGE_EXTERNAL_STORAGE`, which the app no longer holds.
  Future<List<String>> exportMultipleFiles({
    required List<String> sandboxPaths,
    String Function(int index, String sandboxPath)? nameOverride,
  }) async {
    if (Platform.isAndroid) {
      final picked = await PublicStorage.pickFolder();
      if (picked == null) return [];

      final results = <String>[];
      try {
        for (int i = 0; i < sandboxPaths.length; i++) {
          final sandboxPath = sandboxPaths[i];
          if (!await File(sandboxPath).exists()) continue;

          final baseName = nameOverride != null
              ? nameOverride(i, sandboxPath)
              : path.basename(sandboxPath);
          try {
            final destination = await PublicStorage.publishFile(
              sourcePath: sandboxPath,
              fileName: baseName,
              kind: PublicStorage.kindForFileName(baseName),
              treeUriOverride: picked.uri,
            );
            results.add(destination);
          } catch (_) {
            // Skip files that failed; the caller reports totals.
          }
        }
      } finally {
        // One-off export: drop the grant again so it does not linger.
        await PublicStorage.releaseTree(picked.uri);
      }
      return results;
    }

    final dir = await FilePicker.getDirectoryPath(
      dialogTitle: 'Select save location',
    );
    if (dir == null) return [];

    final results = <String>[];
    for (int i = 0; i < sandboxPaths.length; i++) {
      final sandboxPath = sandboxPaths[i];
      final source = File(sandboxPath);
      if (!await source.exists()) continue;

      final baseName = nameOverride != null
          ? nameOverride(i, sandboxPath)
          : path.basename(sandboxPath);
      final destPath = path.join(dir, baseName);
      await source.copy(destPath);
      results.add(destPath);
    }
    return results;
  }

  /// Deletes all sandbox files and the sandbox directory itself.
  /// Safe to call multiple times; no-ops if already cleaned up.
  Future<void> cleanup() async {
    for (final filePath in _sandboxFiles) {
      try {
        final file = File(filePath);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
    }
    _sandboxFiles = [];

    if (_sandboxDir != null && await _sandboxDir!.exists()) {
      try {
        await _sandboxDir!.delete(recursive: true);
      } catch (_) {}
      _sandboxDir = null;
    }
  }

  /// Whether the sandbox currently holds tracked files.
  bool get hasSandboxFiles => _sandboxFiles.isNotEmpty;
}
