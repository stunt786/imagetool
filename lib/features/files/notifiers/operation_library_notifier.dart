import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/operation_folder.dart';
import '../../../core/services/operation_store.dart';
import '../../../core/services/operation_store_provider.dart';

export '../../../core/services/operation_store_provider.dart'
    show operationStoreProvider;

/// Immutable view of the metadata the Files/History UI renders from.
@immutable
class OperationLibrary {
  const OperationLibrary({
    this.isLoading = true,
    this.operations = const <OperationFolder>[],
    this.files = const <AppFileItem>[],
    this.errorMessage,
  });

  final bool isLoading;
  final List<OperationFolder> operations;
  final List<AppFileItem> files;
  final String? errorMessage;

  bool get isEmpty => operations.isEmpty && files.isEmpty;

  int get totalSize =>
      files.fold<int>(0, (sum, item) => sum + item.sizeBytes);

  OperationLibrary copyWith({
    bool? isLoading,
    List<OperationFolder>? operations,
    List<AppFileItem>? files,
    String? errorMessage,
    bool clearError = false,
  }) {
    return OperationLibrary(
      isLoading: isLoading ?? this.isLoading,
      operations: operations ?? this.operations,
      files: files ?? this.files,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

final operationLibraryProvider =
    NotifierProvider<OperationLibraryNotifier, OperationLibrary>(
  OperationLibraryNotifier.new,
);

/// Exposes the operation store to the UI and keeps the view in sync after
/// edits. All filtering/sorting happens in the store, from metadata only.
class OperationLibraryNotifier extends Notifier<OperationLibrary> {
  OperationStore get _store => ref.read(operationStoreProvider);

  @override
  OperationLibrary build() {
    // Stay in sync with every tool that records an operation, without those
    // tools needing to know about this notifier.
    final store = ref.read(operationStoreProvider);
    void listener() => _emit();
    store.addListener(listener);
    ref.onDispose(() => store.removeListener(listener));

    Future<void>.microtask(_load);
    return const OperationLibrary();
  }

  Future<void> _load() async {
    try {
      await _store.load();
      _emit();
    } catch (error) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Your file library could not be loaded.',
      );
    }
  }

  /// Re-reads the in-memory metadata (cheap; no disk walk).
  void refresh() => _emit();

  /// Re-loads from persistence, then drops records whose folder is gone.
  Future<void> reload({bool pruneMissing = false}) async {
    state = state.copyWith(isLoading: true, clearError: true);
    await _store.load();
    if (pruneMissing) {
      await _store.pruneMissing();
    }
    _emit();
  }

  Future<bool> deleteOperation(String operationId) async {
    final ok = await _store.deleteOperation(operationId);
    _emit();
    return ok;
  }

  Future<int> deleteFiles(Iterable<String> fileIds) async {
    var deleted = 0;
    for (final id in fileIds.toList()) {
      if (await _store.deleteFile(id)) deleted++;
    }
    _emit();
    return deleted;
  }

  Future<bool> renameOperation(String operationId, String newName) async {
    final ok = await _store.renameOperation(operationId, newName);
    _emit();
    return ok;
  }

  Future<bool> renameFile(String fileId, String newName) async {
    final ok = await _store.renameFile(fileId, newName);
    _emit();
    return ok;
  }

  Future<bool> updateOperationTags(String operationId, List<String> tags) async {
    final ok = await _store.updateOperationTags(operationId, tags);
    _emit();
    return ok;
  }

  Future<void> reorderFiles(String operationId, List<String> orderedFileIds) async {
    await _store.reorderFiles(operationId, orderedFileIds);
    _emit();
  }

  Future<int> moveFiles(Iterable<String> fileIds, String targetOperationId) async {
    final moved = await _store.moveFiles(fileIds, targetOperationId);
    _emit();
    return moved;
  }

  Future<int> copyFiles(Iterable<String> fileIds, String targetOperationId) async {
    final copied = await _store.copyFiles(fileIds, targetOperationId);
    _emit();
    return copied;
  }

  void _emit() {
    state = OperationLibrary(
      isLoading: false,
      operations: _store.operations,
      files: _store.allFiles,
    );
  }
}
