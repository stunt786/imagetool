import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../models/operation_folder.dart';
import 'operation_recorder.dart';
import 'operation_store.dart';
import 'public_storage.dart';

/// One finished tool output, either as bytes or as an already-written file
/// (typically a working copy that should be moved rather than duplicated).
class OutputEntry {
  const OutputEntry.bytes({
    required Uint8List bytes,
    required this.fileName,
    this.publicKind = PublicFileKind.document,
  })  : _bytes = bytes,
        sourcePath = null;

  const OutputEntry.file({
    required this.sourcePath,
    required this.fileName,
    this.publicKind = PublicFileKind.document,
  }) : _bytes = null;

  final Uint8List? _bytes;
  final String? sourcePath;
  final String fileName;
  final PublicFileKind publicKind;

  Uint8List? get bytes => _bytes;
}

/// Where a saved output lives: [localPath] is the app-managed copy used for
/// sharing and the Files library, [publicPath] is the user-visible destination
/// (null when the public save failed and the SAF export must be offered).
class SavedOutput {
  const SavedOutput({required this.localPath, this.publicPath});

  final String localPath;
  final String? publicPath;
}

/// Ensures that any exported file name has the 'pixeltools_' prefix.
String ensurePixelToolsPrefix(String fileName) {
  final trimmed = fileName.trim();
  final base = path.basename(trimmed);
  if (base.toLowerCase().startsWith('pixeltools')) {
    return base;
  }
  return 'pixeltools_$base';
}

/// Persists finished tool outputs in two steps:
///
/// 1. files are written into the operation's own folder so the Files library
///    stays grouped (falling back to a plain staging directory when the store
///    is unavailable),
/// 2. every output is published to public storage — MediaStore or the SAF
///    folder chosen in Settings — the scoped-storage friendly way.
Future<List<SavedOutput>> saveToolOutputs(
  OperationStore store, {
  required OperationKind kind,
  required List<OutputEntry> entries,
  Directory? stagingDirectory,
}) async {
  if (entries.isEmpty) return const [];

  final placed = List<String?>.filled(entries.length, null);
  OperationSession? session;

  try {
    final started = await OperationRecorder(store)
        .start(kind, expectedItems: entries.length);
    session = started;
    for (var i = 0; i < entries.length; i++) {
      final sanitizedName = ensurePixelToolsPrefix(entries[i].fileName);
      final target = await store.resolveOutputPath(
        Directory(started.directoryPath),
        sanitizedName,
      );
      await _materialize(entries[i], target);
      await started.recordFile(target);
      placed[i] = target;
    }
    await started.complete();
  } catch (error) {
    try {
      await session?.fail('Saving outputs failed: $error');
    } catch (_) {
      // Best effort; the fallback below still keeps the files.
    }
    // A metadata failure must never lose the tool's output: anything not
    // written yet lands in the plain staging directory instead.
    final staging = stagingDirectory ?? await _defaultStagingDirectory();
    await staging.create(recursive: true);
    for (var i = 0; i < entries.length; i++) {
      if (placed[i] != null) continue;
      final sanitizedName = ensurePixelToolsPrefix(entries[i].fileName);
      final target = path.join(staging.path, sanitizedName);
      await _materialize(entries[i], target);
      placed[i] = target;
    }
  }

  final outputs = <SavedOutput>[];
  for (var i = 0; i < entries.length; i++) {
    final localPath = placed[i]!;
    String? publicPath;
    try {
      publicPath = await PublicStorage.publishFile(
        sourcePath: localPath,
        fileName: path.basename(localPath),
        kind: entries[i].publicKind,
      );
    } catch (_) {
      // Keep the local copy; the UI offers the SAF export action instead.
      publicPath = null;
    }
    outputs.add(SavedOutput(localPath: localPath, publicPath: publicPath));
  }

  for (var i = 0; i < entries.length; i++) {
    final source = entries[i].sourcePath;
    if (source == null || source == placed[i]) continue;
    await _deleteQuietly(source);
  }

  return outputs;
}

Future<void> _materialize(OutputEntry entry, String target) async {
  final file = File(target);
  await file.parent.create(recursive: true);

  final source = entry.sourcePath;
  if (source == null) {
    final bytes = entry.bytes;
    if (bytes == null || bytes.isEmpty) {
      throw StateError('"${entry.fileName}" is empty.');
    }
    await file.writeAsBytes(bytes, flush: true);
    return;
  }

  final sourceFile = File(source);
  if (!await sourceFile.exists()) {
    throw StateError('"${path.basename(source)}" is no longer available.');
  }
  if (await sourceFile.length() == 0) {
    throw StateError('"${path.basename(source)}" is empty.');
  }
  if (path.canonicalize(sourceFile.path) == path.canonicalize(target)) {
    return;
  }
  await sourceFile.copy(target);
}

Future<Directory> _defaultStagingDirectory() async {
  final base = await getApplicationDocumentsDirectory();
  return Directory(path.join(base.path, 'PixelTools'));
}

Future<void> _deleteQuietly(String filePath) async {
  try {
    final file = File(filePath);
    if (await file.exists()) {
      await file.delete();
    }
  } catch (_) {
    // Best effort cleanup only.
  }
}
