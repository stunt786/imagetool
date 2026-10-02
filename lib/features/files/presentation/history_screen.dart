import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/models/operation_folder.dart';
import '../notifiers/operation_library_notifier.dart';
import '../services/file_actions.dart';
import '../widgets/file_thumbnail.dart';
import '../widgets/selection_action_bar.dart';
import 'operation_folder_screen.dart';

/// History Screen matching the exact visual design and UX of `history.jpg`.
///
/// Features:
/// - Top Search bar with clear button and blue/orange quick filter pills.
/// - Operation list showing thumbnail, title, `MM/dd/yyyy HH:mm | 📄 N`, and checkbox.
/// - Tapping an operation opens `OperationFolderScreen` (matching `prev.jpg`).
/// - Multi-selection mode with Share, Save to Gallery, Rename (single), and Delete.
/// - Green floating action button leading to document scanner.
class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

enum _HistoryQuickFilter { all, images, pdfs }

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _selected = <String>{};

  String _query = '';
  _HistoryQuickFilter _quickFilter = _HistoryQuickFilter.all;
  bool _busy = false;
  Timer? _searchDebounce;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 260), () {
      if (!mounted) return;
      setState(() => _query = value.trim().toLowerCase());
    });
  }

  bool get _isSelecting => _selected.isNotEmpty;

  void _clearSelection() {
    if (!mounted) return;
    setState(_selected.clear);
  }

  void _toggleSelection(String id) {
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
      } else {
        _selected.add(id);
      }
    });
  }

  List<OperationFolder> _selectedOperations(List<OperationFolder> all) {
    return all.where((op) => _selected.contains(op.id)).toList();
  }

  List<AppFileItem> _filesOf(String operationId) {
    return ref.read(operationStoreProvider).filesFor(operationId).toList();
  }

  List<AppFileItem> _filesForOperations(List<OperationFolder> operations) {
    return [
      for (final op in operations) ..._filesOf(op.id),
    ];
  }

  Future<void> _run(Future<void> Function(List<OperationFolder> items) action,
      List<OperationFolder> all) async {
    if (_busy) return;
    final operations = _selectedOperations(all);
    if (operations.isEmpty) return;
    setState(() => _busy = true);
    try {
      await action(operations);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteSelected(List<OperationFolder> all) async {
    final operations = _selectedOperations(all);
    if (operations.isEmpty) return;
    final fileCount = _filesForOperations(operations).length;
    final confirmed = await FileActions.confirmDelete(
      context,
      title: operations.length == 1
          ? 'Delete this operation?'
          : 'Delete ${operations.length} operations?',
      message: '$fileCount file(s) will be removed from this app. '
          'Copies saved to the gallery are not affected.',
    );
    if (!confirmed) return;
    await _run((items) async {
      final notifier = ref.read(operationLibraryProvider.notifier);
      for (final op in items) {
        await notifier.deleteOperation(op.id);
      }
    }, all);
    _clearSelection();
  }

  Future<void> _renameOperation(OperationFolder operation) async {
    final name = await FileActions.promptForName(
      context,
      title: 'Rename Operation',
      initialValue: operation.displayName,
    );
    if (name == null) return;
    final ok = await ref
        .read(operationLibraryProvider.notifier)
        .renameOperation(operation.id, name);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? 'Renamed to "$name"' : 'Could not rename that item.'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _openOperation(OperationFolder operation) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => OperationFolderScreen(operationId: operation.id),
      ),
    );
  }

  List<OperationFolder> _filterOperations(List<OperationFolder> operations) {
    return operations.where((op) {
      if (_query.isNotEmpty) {
        final matchesName = op.displayName.toLowerCase().contains(_query);
        final matchesKind = op.kind.name.toLowerCase().contains(_query);
        if (!matchesName && !matchesKind) return false;
      }
      if (_quickFilter == _HistoryQuickFilter.pdfs) {
        final isPdfOp = op.kind == OperationKind.imageToPdf ||
            op.kind == OperationKind.pdfMerge ||
            op.kind == OperationKind.pdfSplit ||
            op.kind == OperationKind.pdfCompress;
        if (!isPdfOp) return false;
      } else if (_quickFilter == _HistoryQuickFilter.images) {
        final isPdfOp = op.kind == OperationKind.imageToPdf ||
            op.kind == OperationKind.pdfMerge ||
            op.kind == OperationKind.pdfSplit ||
            op.kind == OperationKind.pdfCompress;
        if (isPdfOp) return false;
      }
      return true;
    }).toList();
  }

  String? _thumbnailFor(OperationFolder operation) {
    if (operation.thumbnailPath != null &&
        File(operation.thumbnailPath!).existsSync() &&
        File(operation.thumbnailPath!).lengthSync() > 0) {
      return operation.thumbnailPath;
    }
    final files = _filesOf(operation.id);
    for (final f in files) {
      final file = File(f.path);
      if (file.existsSync() && file.lengthSync() > 0) {
        return f.path;
      }
    }
    try {
      final dir = Directory(operation.directoryPath);
      if (dir.existsSync()) {
        final entries = dir.listSync().whereType<File>().toList();
        for (final file in entries) {
          final p = file.path.toLowerCase();
          if (p.endsWith('.jpg') ||
              p.endsWith('.jpeg') ||
              p.endsWith('.png') ||
              p.endsWith('.webp') ||
              p.endsWith('.pdf')) {
            if (file.lengthSync() > 0) return file.path;
          }
        }
        if (entries.isNotEmpty && entries.first.lengthSync() > 0) {
          return entries.first.path;
        }
      }
    } catch (_) {}
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final library = ref.watch(operationLibraryProvider);
    final operations = _filterOperations(library.operations);

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF16181D) : theme.colorScheme.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          _isSelecting ? '${_selected.length} selected' : 'History',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          if (_isSelecting)
            TextButton(
              onPressed: () {
                setState(() {
                  if (_selected.length == operations.length) {
                    _selected.clear();
                  } else {
                    _selected
                      ..clear()
                      ..addAll(operations.map((o) => o.id));
                  }
                });
              },
              child: Text(
                _selected.length == operations.length
                    ? 'Deselect All'
                    : 'Select All',
                style: const TextStyle(
                  color: Color(0xFF00E5FF),
                  fontWeight: FontWeight.w700,
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.check_box_outlined),
              tooltip: 'Select',
              onPressed: () {
                if (operations.isNotEmpty) {
                  _toggleSelection(operations.first.id);
                }
              },
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Top Search Bar + Filter Pills (matching history.jpg)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 48,
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF1E2129)
                            : theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: TextField(
                        controller: _searchController,
                        onChanged: _onSearchChanged,
                        textInputAction: TextInputAction.search,
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black87,
                          fontSize: 15,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Search',
                          hintStyle: TextStyle(
                            color: isDark ? Colors.white38 : Colors.black38,
                          ),
                          prefixIcon: Icon(
                            Icons.search_rounded,
                            color: isDark ? Colors.white54 : Colors.black45,
                          ),
                          suffixIcon: _searchController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.close_rounded, size: 18),
                                  onPressed: () {
                                    _searchController.clear();
                                    _searchDebounce?.cancel();
                                    setState(() => _query = '');
                                  },
                                )
                              : null,
                          border: InputBorder.none,
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Blue filter pill (history.jpg)
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () {
                      setState(() {
                        _quickFilter =
                            _quickFilter == _HistoryQuickFilter.images
                                ? _HistoryQuickFilter.all
                                : _HistoryQuickFilter.images;
                      });
                    },
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: const Color(0xFF4C82FB),
                        borderRadius: BorderRadius.circular(8),
                        border: _quickFilter == _HistoryQuickFilter.images
                            ? Border.all(color: Colors.white, width: 2)
                            : null,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Orange filter pill (history.jpg)
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () {
                      setState(() {
                        _quickFilter = _quickFilter == _HistoryQuickFilter.pdfs
                            ? _HistoryQuickFilter.all
                            : _HistoryQuickFilter.pdfs;
                      });
                    },
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEAA24B),
                        borderRadius: BorderRadius.circular(8),
                        border: _quickFilter == _HistoryQuickFilter.pdfs
                            ? Border.all(color: Colors.white, width: 2)
                            : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Operation List
            Expanded(
              child: operations.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _query.isNotEmpty
                                ? Icons.search_off_rounded
                                : Icons.history_rounded,
                            size: 64,
                            color: Colors.white38,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _query.isNotEmpty
                                ? 'No results found'
                                : 'No history yet',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: isDark ? Colors.white70 : Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
                      itemCount: operations.length,
                      separatorBuilder: (_, __) => Divider(
                        height: 1,
                        color: Colors.white.withValues(alpha: 0.05),
                      ),
                      itemBuilder: (context, index) {
                        final op = operations[index];
                        final selected = _selected.contains(op.id);
                        final dateStr =
                            DateFormat('MM/dd/yyyy HH:mm').format(op.createdAt);

                        return InkWell(
                          onTap: () {
                            if (_isSelecting) {
                              _toggleSelection(op.id);
                            } else {
                              _openOperation(op);
                            }
                          },
                          onLongPress: () => _toggleSelection(op.id),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: Row(
                              children: [
                                // Thumbnail matching history.jpg
                                FileThumbnail(
                                  path: _thumbnailFor(op) ?? '',
                                  isPdf: (_thumbnailFor(op) ?? '')
                                          .toLowerCase()
                                          .endsWith('.pdf') ||
                                      op.kind == OperationKind.imageToPdf ||
                                      op.kind == OperationKind.pdfMerge ||
                                      op.kind == OperationKind.pdfSplit ||
                                      op.kind == OperationKind.pdfCompress,
                                  size: 58,
                                  borderRadius: 10,
                                ),
                                const SizedBox(width: 14),

                                // Title and Date / Page count
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        op.displayName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 15,
                                          color: isDark
                                              ? Colors.white
                                              : Colors.black87,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          Text(
                                            dateStr,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: isDark
                                                  ? Colors.white54
                                                  : Colors.black54,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            '|',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: isDark
                                                  ? Colors.white30
                                                  : Colors.black26,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Icon(
                                            Icons.description_outlined,
                                            size: 13,
                                            color: isDark
                                                ? Colors.white54
                                                : Colors.black54,
                                          ),
                                          const SizedBox(width: 3),
                                          Text(
                                            '${op.itemCount}',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: isDark
                                                  ? Colors.white54
                                                  : Colors.black54,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),

                                // Checkbox on the right (history.jpg)
                                Checkbox(
                                  value: selected,
                                  onChanged: (_) => _toggleSelection(op.id),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  side: BorderSide(
                                    color: isDark
                                        ? Colors.white38
                                        : Colors.black38,
                                    width: 1.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      // Floating Green Action Button (matching history.jpg)
      floatingActionButton: _isSelecting
          ? null
          : FloatingActionButton(
              backgroundColor: const Color(0xFF00E676),
              foregroundColor: Colors.black,
              elevation: 4,
              onPressed: () => context.push('/camera'),
              child: const Icon(Icons.document_scanner_rounded, size: 28),
            ),
      // Selection Action Bar at the bottom
      bottomNavigationBar: _isSelecting
          ? SelectionActionBar(
              actions: [
                SelectionAction(
                  icon: Icons.share_outlined,
                  label: 'Share',
                  onTap: _busy
                      ? null
                      : () => _run(
                            (items) => FileActions.share(
                              context,
                              _filesForOperations(items),
                            ),
                            operations,
                          ),
                ),
                SelectionAction(
                  icon: Icons.download_outlined,
                  label: 'Save',
                  onTap: _busy
                      ? null
                      : () => _run(
                            (items) => FileActions.save(
                              context,
                              _filesForOperations(items),
                            ),
                            operations,
                          ),
                ),
                if (_selected.length == 1)
                  SelectionAction(
                    icon: Icons.drive_file_rename_outline,
                    label: 'Rename',
                    onTap: _busy
                        ? null
                        : () {
                            final ops = _selectedOperations(operations);
                            if (ops.isNotEmpty) _renameOperation(ops.first);
                          },
                  ),
                SelectionAction(
                  icon: Icons.delete_outline,
                  label: 'Delete',
                  destructive: true,
                  onTap: _busy ? null : () => _deleteSelected(operations),
                ),
              ],
            )
          : null,
    );
  }
}
