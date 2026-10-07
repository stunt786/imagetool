import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as path;

import '../models/operation_folder.dart';
import 'operation_store.dart';

/// Convenience wrapper that turns "one tool run" into an operation
/// transaction.
///
/// Usage:
/// ```dart
/// final session = await OperationRecorder(store)
///     .start(OperationKind.resize, expectedItems: images.length);
/// try {
///   for (final image in images) {
///     await session.saveBytes(bytes, 'image_001.jpg');
///   }
///   await session.complete();
/// } catch (e) {
///   await session.fail('$e');
/// }
/// ```
class OperationRecorder {
  const OperationRecorder(this._store);

  final OperationStore _store;

  Future<OperationSession> start(
    OperationKind kind, {
    int expectedItems = 0,
    DateTime? at,
  }) async {
    final directory = await _store.createOperationDirectory(kind, at: at);
    final operation = await _store.beginOperation(
      kind: kind,
      directory: directory,
      expectedItems: expectedItems,
      at: at,
    );
    return OperationSession._(_store, operation);
  }

  /// Reopens an existing operation so more outputs can be appended to it
  /// (used by Files → "Add Pages" for scans).
  ///
  /// Returns `null` when the operation no longer exists.
  Future<OperationSession?> open(String operationId) async {
    await _store.load();
    final operation = _store.operationById(operationId);
    if (operation == null) return null;
    return OperationSession._(_store, operation);
  }
}

/// An in-progress operation. Its output directory is stable, and nothing is
/// marked complete until [complete] is called.
class OperationSession {
  OperationSession._(this._store, this.operation);

  final OperationStore _store;
  final OperationFolder operation;

  String get operationId => operation.id;

  String get directoryPath => operation.directoryPath;

  Directory get directory => Directory(operation.directoryPath);

  /// Writes [bytes] into the operation folder (never overwriting a previous
  /// result) and records it in the metadata.
  Future<AppFileItem?> saveBytes(
    Uint8List bytes,
    String fileName, {
    String? thumbnailPath,
    int? pageCount,
  }) async {
    final target = await _store.resolveOutputPath(directory, fileName);
    final file = File(target);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
    return recordFile(target, thumbnailPath: thumbnailPath, pageCount: pageCount);
  }

  /// Records a file that was written somewhere else (for example by a service
  /// that owns its own output path). Ensures the file is stored inside the
  /// operation's own folder.
  Future<AppFileItem?> recordFile(
    String filePath, {
    String? thumbnailPath,
    int? pageCount,
    String? displayName,
  }) async {
    var finalPath = filePath;
    try {
      final file = File(filePath);
      if (await file.exists()) {
        final opDir = Directory(operation.directoryPath);
        final fileParent = path.canonicalize(file.parent.path);
        final opDirPath = path.canonicalize(opDir.path);
        if (fileParent != opDirPath) {
          final target = await _store.resolveOutputPath(
            opDir,
            displayName ?? path.basename(filePath),
          );
          await file.copy(target);
          finalPath = target;
        }
      }
    } catch (_) {}
    return _store.addOutputFile(
      operationId: operation.id,
      filePath: finalPath,
      thumbnailPath: thumbnailPath,
      pageCount: pageCount,
      displayName: displayName,
    );
  }

  /// Marks the run complete. Call only once every output has been recorded.
  Future<void> complete() => _store.markCompleted(operation.id);

  /// Marks the run failed while keeping whatever was produced.
  Future<void> fail(String message) => _store.markFailed(operation.id, message);

  Future<void> cancel() => _store.markCancelled(operation.id);
}

/// Records one or more already-written files as a completed one-shot
/// operation. Best effort: never throws, so it cannot break a tool's save.
Future<OperationFolder?> recordCompletedOperation(
  OperationStore store,
  OperationKind kind,
  List<String> filePaths, {
  int? expectedItems,
}) async {
  final paths = filePaths.where((p) => p.isNotEmpty).toList();
  if (paths.isEmpty) return null;
  try {
    final session = await OperationRecorder(store)
        .start(kind, expectedItems: expectedItems ?? paths.length);
    for (final path in paths) {
      await session.recordFile(path);
    }
    await session.complete();
    return session.operation;
  } catch (_) {
    return null;
  }
}

/// Small helpers shared by tools that own their file naming.
abstract final class OutputNames {
  /// `image_001.jpg`-style index names, zero padded for stable sorting.
  static String indexed(String extension, int index, {int pad = 3}) {
    final safeExtension = extension.replaceFirst('.', '').toLowerCase();
    return 'image_${(index + 1).toString().padLeft(pad, '0')}.$safeExtension';
  }

  /// Keeps the original name but guarantees a usable extension.
  static String fromSource(String sourceName, String fallbackExtension) {
    final base = path.basenameWithoutExtension(sourceName);
    final extension = path.extension(sourceName).replaceFirst('.', '');
    final safeBase = base.trim().isEmpty ? 'output' : base;
    return '$safeBase.${extension.isEmpty ? fallbackExtension : extension}';
  }
}
