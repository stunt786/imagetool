import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/operation_folder.dart';
import '../utils/file_type_detector.dart';

/// Persistent, metadata-first store for processed files.
///
/// Every tool run creates one [OperationFolder] on disk
/// (`PixelTools/operations/<Tool>/<timestamp>/`) plus one [OperationFolder]
/// record containing its [AppFileItem]s. Files and History then read from this
/// metadata instead of walking the filesystem, which keeps scrolling and
/// search fast.
class OperationStore extends ChangeNotifier {
  OperationStore({
    Future<Directory> Function()? baseDirectoryProvider,
    this.maxOperations = 200,
  }) : _baseDirectoryProvider = baseDirectoryProvider ?? _defaultBaseDirectory;

  static const String _operationsKey = 'operation_folders_v1';
  static const String _filesKey = 'operation_files_v1';
  static const String _rootFolderName = 'operations';

  final Future<Directory> Function() _baseDirectoryProvider;

  /// Retention cap; oldest operations are trimmed from metadata only.
  final int maxOperations;

  final List<OperationFolder> _operations = <OperationFolder>[];
  final List<AppFileItem> _files = <AppFileItem>[];

  bool _loaded = false;
  Future<void>? _loading;

  static Future<Directory> _defaultBaseDirectory() async {
    final documents = await getApplicationDocumentsDirectory();
    return Directory(path.join(documents.path, 'PixelTools'));
  }

  bool get isLoaded => _loaded;

  /// Newest first.
  List<OperationFolder> get operations {
    final copy = List<OperationFolder>.from(_operations)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return List<OperationFolder>.unmodifiable(copy);
  }

  List<AppFileItem> get allFiles => List<AppFileItem>.unmodifiable(_files);

  int get operationCount => _operations.length;

  int get fileCount => _files.length;

  List<AppFileItem> filesFor(String operationId) {
    final items = _files.where((f) => f.operationId == operationId).toList()
      ..sort((a, b) => a.fileName.compareTo(b.fileName));
    return List<AppFileItem>.unmodifiable(items);
  }

  OperationFolder? operationById(String id) {
    for (final operation in _operations) {
      if (operation.id == id) return operation;
    }
    return null;
  }

  AppFileItem? fileById(String id) {
    for (final file in _files) {
      if (file.id == id) return file;
    }
    return null;
  }

  /// Loads persisted metadata. Safe to call repeatedly.
  Future<void> load() {
    if (_loaded) return Future<void>.value();
    return _loading ??= _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _operations
        ..clear()
        ..addAll(_decodeList(prefs.getString(_operationsKey))
            .map(OperationFolder.fromJson)
            .whereType<OperationFolder>());
      _files
        ..clear()
        ..addAll(_decodeList(prefs.getString(_filesKey))
            .map(AppFileItem.fromJson)
            .whereType<AppFileItem>());
      _sortAndTrim();
    } catch (_) {
      // A corrupt store must not stop the app from starting.
      _operations.clear();
      _files.clear();
    }
    _loaded = true;
  }

  List<Map<String, Object?>> _decodeList(String? raw) {
    if (raw == null || raw.isEmpty) return const <Map<String, Object?>>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const <Map<String, Object?>>[];
      return decoded
          .whereType<Map<dynamic, dynamic>>()
          .map((entry) => entry.cast<String, Object?>())
          .toList();
    } catch (_) {
      return const <Map<String, Object?>>[];
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _operationsKey,
        jsonEncode(_operations.map((o) => o.toJson()).toList()),
      );
      await prefs.setString(
        _filesKey,
        jsonEncode(_files.map((f) => f.toJson()).toList()),
      );
    } catch (_) {
      // Persisting is best effort; the in-memory model stays authoritative for
      // the current session.
    }
  }

  void _sortAndTrim() {
    _operations.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (_operations.length > maxOperations) {
      final removed = _operations.sublist(maxOperations);
      _operations.removeRange(maxOperations, _operations.length);
      final removedIds = removed.map((o) => o.id).toSet();
      _files.removeWhere((f) => removedIds.contains(f.operationId));
    }
  }

  // ─── Creating operations ──────────────────────────────────────────────────

  /// Directory for one run of [kind], e.g.
  /// `PixelTools/operations/Image_to_PDF/20260927_191530`.
  Future<Directory> createOperationDirectory(
    OperationKind kind, {
    DateTime? at,
  }) async {
    final base = await _baseDirectoryProvider();
    final stamp = _timestamp(at ?? DateTime.now());
    final directory = Directory(
      path.join(base.path, _rootFolderName, kind.folderName, stamp),
    );
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  /// Starts a transaction. The operation stays [OperationStatus.processing]
  /// until [markCompleted] is called.
  Future<OperationFolder> beginOperation({
    required OperationKind kind,
    required Directory directory,
    int expectedItems = 0,
    DateTime? at,
  }) async {
    await load();
    final created = at ?? DateTime.now();
    final operation = OperationFolder(
      id: 'op_${created.microsecondsSinceEpoch}_${_operations.length}',
      kind: kind,
      displayName: OperationFolder.buildDisplayName(kind, created),
      directoryPath: directory.path,
      createdAt: created,
      modifiedAt: created,
      expectedItems: expectedItems,
      status: OperationStatus.processing,
    );
    _operations.insert(0, operation);
    _sortAndTrim();
    await _persist();
    notifyListeners();
    return operation;
  }

  /// Records one produced file, resolving name collisions so an existing file
  /// is never overwritten.
  Future<AppFileItem?> addOutputFile({
    required String operationId,
    required String filePath,
    String? thumbnailPath,
    int? pageCount,
    String? displayName,
  }) async {
    await load();
    final operation = operationById(operationId);
    if (operation == null) return null;

    final file = File(filePath);
    if (!await file.exists()) return null;

    // Tools resolve collisions with [resolveOutputPath] before writing, so the
    // file here is already final.
    final resolvedPath = filePath;
    final fileName = displayName ?? path.basename(resolvedPath);
    final detected = FileTypeDetector.detect(path: resolvedPath);
    final existing = _files.where((f) => f.operationId == operationId).length;

    final item = AppFileItem(
      id: 'file_${DateTime.now().microsecondsSinceEpoch}_$existing',
      operationId: operationId,
      path: resolvedPath,
      fileName: fileName,
      extension: detected.extension,
      mimeType: detected.mimeType,
      sizeBytes: await File(resolvedPath).length(),
      createdAt: DateTime.now(),
      isPdf: detected.isPdf,
      isImage: detected.isImage,
      thumbnailPath: thumbnailPath,
      pageCount: pageCount,
    );
    _files.add(item);

    final candidateThumb = thumbnailPath ??
        (detected.isImage || detected.isPdf ? resolvedPath : null);
    _replaceOperation(
      operation.copyWith(
        itemCount: existing + 1,
        modifiedAt: DateTime.now(),
        thumbnailPath: (operation.thumbnailPath != null &&
                File(operation.thumbnailPath!).existsSync())
            ? operation.thumbnailPath
            : (candidateThumb ?? operation.thumbnailPath),
      ),
    );
    await _persist();
    notifyListeners();
    return item;
  }

  /// Marks the operation complete. Only call this once every output exists.
  Future<void> markCompleted(String operationId) async {
    await load();
    final operation = operationById(operationId);
    if (operation == null) return;
    _replaceOperation(
      operation.copyWith(
        status: OperationStatus.completed,
        modifiedAt: DateTime.now(),
        clearError: true,
      ),
    );
    await _persist();
    notifyListeners();
  }

  /// Records a failure while keeping the partial results that were written.
  Future<void> markFailed(String operationId, String message) async {
    await load();
    final operation = operationById(operationId);
    if (operation == null) return;
    _replaceOperation(
      operation.copyWith(
        status: OperationStatus.failed,
        errorMessage: message,
        modifiedAt: DateTime.now(),
      ),
    );
    await _persist();
    notifyListeners();
  }

  Future<void> markCancelled(String operationId) async {
    await load();
    final operation = operationById(operationId);
    if (operation == null) return;
    _replaceOperation(
      operation.copyWith(
        status: OperationStatus.cancelled,
        modifiedAt: DateTime.now(),
      ),
    );
    await _persist();
    notifyListeners();
  }

  // ─── Editing ──────────────────────────────────────────────────────────────

  /// Renames the operation label only; the directory keeps its stable id-based
  /// path so nothing on disk has to move.
  Future<bool> renameOperation(String operationId, String newName) async {
    await load();
    final trimmed = newName.trim();
    if (trimmed.isEmpty) return false;
    final operation = operationById(operationId);
    if (operation == null) return false;
    _replaceOperation(
      operation.copyWith(displayName: trimmed, modifiedAt: DateTime.now()),
    );
    await _persist();
    notifyListeners();
    return true;
  }

  /// Renames the file on disk and in the metadata.
  Future<bool> renameFile(String fileId, String newName) async {
    await load();
    final item = fileById(fileId);
    if (item == null) return false;

    final safeName = normalizeRename(newName, item.fileName);
    if (safeName == item.fileName) return true;

    final directory = File(item.path).parent;
    var targetPath = path.join(directory.path, safeName);

    // Never clobber an unrelated file.
    if (await File(targetPath).exists()) {
      targetPath = await _resolveCollision(targetPath);
    }

    try {
      File renamed;
      try {
        renamed = await File(item.path).rename(targetPath);
      } on FileSystemException {
        final copied = await File(item.path).copy(targetPath);
        try {
          await File(item.path).delete();
        } catch (_) {}
        renamed = copied;
      }
      final detected = FileTypeDetector.detect(path: targetPath);
      _replaceFile(
        item.copyWith(
          path: renamed.path,
          fileName: path.basename(targetPath),
          extension: detected.extension,
          mimeType: detected.mimeType,
          sizeBytes: await renamed.length(),
        ),
      );
      final operation = operationById(item.operationId);
      if (operation != null) {
        _replaceOperation(operation.copyWith(
          modifiedAt: DateTime.now(),
          thumbnailPath: operation.thumbnailPath == item.path
              ? renamed.path
              : operation.thumbnailPath,
        ));
      }
      await _persist();
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Updates tags for an operation.
  Future<bool> updateOperationTags(String operationId, List<String> tags) async {
    await load();
    final operation = operationById(operationId);
    if (operation == null) return false;
    _replaceOperation(
      operation.copyWith(tags: tags, modifiedAt: DateTime.now()),
    );
    await _persist();
    notifyListeners();
    return true;
  }

  /// Reorders files within an operation folder.
  Future<void> reorderFiles(String operationId, List<String> orderedFileIds) async {
    await load();
    final opFiles = _files.where((f) => f.operationId == operationId).toList();
    if (opFiles.isEmpty) return;

    // Create a map of id -> file
    final map = {for (final f in opFiles) f.id: f};
    final reordered = <AppFileItem>[];
    for (final id in orderedFileIds) {
      final f = map.remove(id);
      if (f != null) reordered.add(f);
    }
    // Add any remaining
    reordered.addAll(map.values);

    _files.removeWhere((f) => f.operationId == operationId);
    _files.addAll(reordered);
    final op = operationById(operationId);
    if (op != null && reordered.isNotEmpty) {
      _replaceOperation(op.copyWith(
        modifiedAt: DateTime.now(),
        thumbnailPath: reordered.first.thumbnailPath ?? reordered.first.path,
      ));
    }
    await _persist();
    notifyListeners();
  }

  /// Moves files from their current operation to [targetOperationId].
  Future<int> moveFiles(Iterable<String> fileIds, String targetOperationId) async {
    await load();
    final targetOp = operationById(targetOperationId);
    if (targetOp == null) return 0;
    final targetDir = Directory(targetOp.directoryPath);
    await targetDir.create(recursive: true);

    var moved = 0;
    final affectedOpIds = <String>{targetOperationId};
    for (final id in fileIds) {
      final item = fileById(id);
      if (item == null || item.operationId == targetOperationId) continue;
      affectedOpIds.add(item.operationId);
      try {
        final src = File(item.path);
        final dest = await resolveOutputPath(targetDir, item.fileName);
        if (await src.exists()) {
          try {
            await src.rename(dest);
          } on FileSystemException {
            await src.copy(dest);
            try {
              await src.delete();
            } catch (_) {}
          }
        }
        _replaceFile(item.copyWith(
          path: dest,
          fileName: path.basename(dest),
        ));
        // Update operationId
        final idx = _files.indexWhere((f) => f.id == id);
        if (idx != -1) {
          _files[idx] = AppFileItem(
            id: item.id,
            operationId: targetOperationId,
            path: dest,
            fileName: path.basename(dest),
            extension: item.extension,
            mimeType: item.mimeType,
            sizeBytes: item.sizeBytes,
            createdAt: item.createdAt,
            isPdf: item.isPdf,
            isImage: item.isImage,
            thumbnailPath: item.thumbnailPath,
            pageCount: item.pageCount,
          );
        }
        moved++;
      } catch (_) {}
    }

    // Refresh operation metadata (item counts and thumbnails) for all affected folders
    for (final opId in affectedOpIds) {
      final op = operationById(opId);
      if (op != null) {
        final opFiles = filesFor(opId).toList();
        _replaceOperation(op.copyWith(
          itemCount: opFiles.length,
          modifiedAt: DateTime.now(),
          thumbnailPath: opFiles.isNotEmpty
              ? (opFiles.first.thumbnailPath ?? opFiles.first.path)
              : null,
        ));
      }
    }

    _sortAndTrim();
    await _persist();
    notifyListeners();
    return moved;
  }

  /// Copies files into [targetOperationId].
  Future<int> copyFiles(Iterable<String> fileIds, String targetOperationId) async {
    await load();
    final targetOp = operationById(targetOperationId);
    if (targetOp == null) return 0;
    final targetDir = Directory(targetOp.directoryPath);
    await targetDir.create(recursive: true);

    var copied = 0;
    for (final id in fileIds) {
      final item = fileById(id);
      if (item == null) continue;
      try {
        final src = File(item.path);
        final dest = await resolveOutputPath(targetDir, 'copy_${item.fileName}');
        if (await src.exists()) {
          await src.copy(dest);
        }
        await addOutputFile(
          operationId: targetOperationId,
          filePath: dest,
          displayName: path.basename(dest),
        );
        copied++;
      } catch (_) {}
    }
    return copied;
  }

  /// Deletes an operation and everything it produced from app storage.
  ///
  /// The device gallery is never touched: only the app-owned folder is removed.
  Future<bool> deleteOperation(String operationId) async {
    await load();
    final operation = operationById(operationId);
    if (operation == null) return false;

    try {
      final directory = Directory(operation.directoryPath);
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    } catch (_) {
      // Keep going: metadata must not go stale even if the folder is locked.
    }

    _operations.removeWhere((o) => o.id == operationId);
    _files.removeWhere((f) => f.operationId == operationId);
    await _persist();
    notifyListeners();
    return true;
  }

  Future<bool> deleteFile(String fileId) async {
    await load();
    final item = fileById(fileId);
    if (item == null) return false;

    try {
      final file = File(item.path);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Ignore filesystem errors and drop the record anyway.
    }

    _files.removeWhere((f) => f.id == fileId);
    final operation = operationById(item.operationId);
    if (operation != null) {
      _replaceOperation(
        operation.copyWith(
          itemCount: filesFor(operation.id).length,
          modifiedAt: DateTime.now(),
        ),
      );
    }
    await _persist();
    notifyListeners();
    return true;
  }

  /// Drops records whose folder no longer exists (e.g. cleared by the system).
  Future<int> pruneMissing() async {
    await load();
    final missing = <String>[];
    for (final operation in _operations) {
      if (!await Directory(operation.directoryPath).exists()) {
        missing.add(operation.id);
      }
    }
    if (missing.isEmpty) return 0;
    _operations.removeWhere((o) => missing.contains(o.id));
    _files.removeWhere((f) => missing.contains(f.operationId));
    await _persist();
    notifyListeners();
    return missing.length;
  }

  Future<void> clearAll() async {
    await load();
    _operations.clear();
    _files.clear();
    await _persist();
    notifyListeners();
  }

  // ─── Queries ──────────────────────────────────────────────────────────────

  /// Filters and sorts operations from metadata only (no disk access).
  List<OperationFolder> queryOperations({
    String search = '',
    FileFilter filter = FileFilter.all,
    FileSortOrder sort = FileSortOrder.newestFirst,
  }) {
    var result = _operations.where((operation) {
      if (filter == FileFilter.images || filter == FileFilter.pdfs) {
        final items = filesFor(operation.id);
        final matches = filter == FileFilter.images
            ? items.any((item) => item.isImage)
            : items.any((item) => item.isPdf);
        if (!matches) return false;
      } else if (filter == FileFilter.recent) {
        if (DateTime.now().difference(operation.createdAt).inDays > 7) {
          return false;
        }
      }
      return _matchesSearch(
        search,
        <String>[operation.displayName, operation.kind.label],
      );
    }).toList();

    _sortOperations(result, sort);
    return List<OperationFolder>.unmodifiable(result);
  }

  /// All files across every operation, filtered and sorted from metadata.
  List<AppFileItem> queryFiles({
    String search = '',
    FileFilter filter = FileFilter.all,
    FileSortOrder sort = FileSortOrder.newestFirst,
    String? operationId,
  }) {
    var result = _files.where((item) {
      if (operationId != null && item.operationId != operationId) return false;
      switch (filter) {
        case FileFilter.images:
          if (!item.isImage) return false;
          break;
        case FileFilter.pdfs:
          if (!item.isPdf) return false;
          break;
        case FileFilter.recent:
          if (DateTime.now().difference(item.createdAt).inDays > 7) {
            return false;
          }
          break;
        case FileFilter.all:
          break;
      }
      return _matchesSearch(
        search,
        <String>[item.fileName, item.extension, item.mimeType],
      );
    }).toList();

    _sortFiles(result, sort);
    return List<AppFileItem>.unmodifiable(result);
  }

  static bool _matchesSearch(String query, List<String> fields) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return true;
    for (final field in fields) {
      if (field.toLowerCase().contains(needle)) return true;
    }
    return false;
  }

  void _sortOperations(List<OperationFolder> items, FileSortOrder sort) {
    switch (sort) {
      case FileSortOrder.newestFirst:
        items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        break;
      case FileSortOrder.oldestFirst:
        items.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        break;
      case FileSortOrder.nameAsc:
        items.sort((a, b) =>
            a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
        break;
      case FileSortOrder.nameDesc:
        items.sort((a, b) =>
            b.displayName.toLowerCase().compareTo(a.displayName.toLowerCase()));
        break;
      case FileSortOrder.sizeDesc:
        items.sort((a, b) => _operationSize(b).compareTo(_operationSize(a)));
        break;
      case FileSortOrder.sizeAsc:
        items.sort((a, b) => _operationSize(a).compareTo(_operationSize(b)));
        break;
    }
  }

  void _sortFiles(List<AppFileItem> items, FileSortOrder sort) {
    switch (sort) {
      case FileSortOrder.newestFirst:
        items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        break;
      case FileSortOrder.oldestFirst:
        items.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        break;
      case FileSortOrder.nameAsc:
        items.sort((a, b) =>
            a.fileName.toLowerCase().compareTo(b.fileName.toLowerCase()));
        break;
      case FileSortOrder.nameDesc:
        items.sort((a, b) =>
            b.fileName.toLowerCase().compareTo(a.fileName.toLowerCase()));
        break;
      case FileSortOrder.sizeDesc:
        items.sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));
        break;
      case FileSortOrder.sizeAsc:
        items.sort((a, b) => a.sizeBytes.compareTo(b.sizeBytes));
        break;
    }
  }

  int _operationSize(OperationFolder operation) => filesFor(operation.id)
      .fold<int>(0, (sum, item) => sum + item.sizeBytes);

  // ─── Name helpers ─────────────────────────────────────────────────────────

  /// Strips characters that are illegal in file names.
  static String sanitizeFileName(String input) {
    var name = input.trim().replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_');
    name = name.replaceAll(RegExp(r'\s+'), ' ');
    if (name.isEmpty || name == '.' || name == '..') name = 'untitled';
    return name;
  }

  /// Normalises a user-supplied rename so extensions behave predictably and
  /// `photo.jpg.jpg` can never be produced.
  static String normalizeRename(String requested, String currentFileName) {
    final sanitized = sanitizeFileName(requested);
    final currentExtension = FileTypeDetector.extensionOf(currentFileName);
    if (currentExtension.isEmpty) return sanitized;

    final requestedExtension = FileTypeDetector.extensionOf(sanitized);
    if (requestedExtension.isEmpty) return '$sanitized.$currentExtension';

    if (requestedExtension.toLowerCase() == currentExtension.toLowerCase()) {
      final withoutExtension = sanitized
          .substring(0, sanitized.length - currentExtension.length - 1);
      if (withoutExtension.toLowerCase().endsWith(
            '.${currentExtension.toLowerCase()}',
          )) {
        return withoutExtension;
      }
      return sanitized;
    }
    return sanitized;
  }

  /// Returns a path inside [directory] for [fileName] that does not exist yet.
  ///
  /// Tools call this **before** writing so an existing result is never
  /// overwritten (`photo.jpg`, `photo_1.jpg`, `photo_2.jpg`, …).
  Future<String> resolveOutputPath(Directory directory, String fileName) {
    final safeName = sanitizeFileName(fileName);
    return _resolveCollision(path.join(directory.path, safeName));
  }

  /// Returns [targetPath], or a `_1`, `_2`… variant when it already exists.
  Future<String> _resolveCollision(String targetPath) async {
    if (!await File(targetPath).exists()) return targetPath;
    final directory = path.dirname(targetPath);
    final extension = path.extension(targetPath);
    final base = path.basenameWithoutExtension(targetPath);
    var index = 1;
    while (index < 1000) {
      final candidate = path.join(directory, '${base}_$index$extension');
      if (!await File(candidate).exists()) return candidate;
      index++;
    }
    return path.join(
      directory,
      '${base}_${DateTime.now().millisecondsSinceEpoch}$extension',
    );
  }

  void _replaceOperation(OperationFolder operation) {
    final index = _operations.indexWhere((o) => o.id == operation.id);
    if (index == -1) {
      _operations.insert(0, operation);
    } else {
      _operations[index] = operation;
    }
  }

  void _replaceFile(AppFileItem item) {
    final index = _files.indexWhere((f) => f.id == item.id);
    if (index == -1) {
      _files.add(item);
    } else {
      _files[index] = item;
    }
  }

  static String _timestamp(DateTime at) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${at.year}${two(at.month)}${two(at.day)}_'
        '${two(at.hour)}${two(at.minute)}${two(at.second)}';
  }
}
