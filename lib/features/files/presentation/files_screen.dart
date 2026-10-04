import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/models/operation_folder.dart';
import '../notifiers/operation_library_notifier.dart';
import '../services/file_actions.dart';
import '../widgets/file_thumbnail.dart';
import '../widgets/selection_action_bar.dart';
import 'operation_folder_screen.dart';

/// Files: a metadata-backed file manager over the operation folders.
///
/// Layout follows the `files.jpg` / `history.jpg` references — a filter header
/// with sort / view / select controls, a search field, and one row per
/// operation showing a thumbnail, name, date and item count.
class FilesScreen extends ConsumerStatefulWidget {
  const FilesScreen({super.key});

  @override
  ConsumerState<FilesScreen> createState() => _FilesScreenState();
}

class _FilesScreenState extends ConsumerState<FilesScreen> {
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _selected = <String>{};

  FileFilter _filter = FileFilter.all;
  FileSortOrder _sort = FileSortOrder.newestFirst;
  String _query = '';
  bool _gridView = false;
  bool _busy = false;
  Timer? _searchDebounce;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    // Debounced so typing never triggers a filter pass per keystroke.
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 280), () {
      if (!mounted) return;
      setState(() => _query = value);
    });
  }

  List<OperationFolder> _visibleOperations(OperationLibrary library) {
    // Filtering and sorting happen in the store, from metadata only.
    return ref.read(operationStoreProvider).queryOperations(
          search: _query,
          filter: _filter,
          sort: _sort,
        );
  }

  List<AppFileItem> _filesOf(String operationId) {
    return ref
        .read(operationStoreProvider)
        .filesFor(operationId)
        .toList(growable: false);
  }

  bool get _isSelecting => _selected.isNotEmpty;

  void _clearSelection() {
    if (!mounted) return;
    setState(_selected.clear);
  }

  List<OperationFolder> _selectedOperations() {
    final library = ref.read(operationLibraryProvider);
    return library.operations
        .where((operation) => _selected.contains(operation.id))
        .toList();
  }

  List<AppFileItem> _filesForOperations(List<OperationFolder> operations) {
    return [
      for (final operation in operations) ..._filesOf(operation.id),
    ];
  }

  Future<void> _run(
    Future<void> Function(List<OperationFolder> items) action,
  ) async {
    if (_busy) return;
    final operations = _selectedOperations();
    if (operations.isEmpty) return;
    setState(() => _busy = true);
    try {
      await action(operations);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteSelected() async {
    final operations = _selectedOperations();
    if (operations.isEmpty) return;
    final fileCount = _filesForOperations(operations).length;
    final confirmed = await FileActions.confirmDelete(
      context,
      title: operations.length == 1
          ? 'Delete this operation?'
          : 'Delete ${operations.length} operations?',
      message: '$fileCount file(s) will be removed from this app. '
          'Copies you saved to the gallery are not affected.',
    );
    if (!confirmed) return;
    await _run((items) async {
      final notifier = ref.read(operationLibraryProvider.notifier);
      for (final operation in items) {
        await notifier.deleteOperation(operation.id);
      }
    });
    _clearSelection();
  }

  Future<void> _openOperation(OperationFolder operation) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => OperationFolderScreen(operationId: operation.id),
      ),
    );
  }

  Future<void> _renameOperation(OperationFolder operation) async {
    final name = await FileActions.promptForName(
      context,
      title: 'Rename operation',
      initialValue: operation.displayName,
    );
    if (name == null) return;
    final ok = await ref
        .read(operationLibraryProvider.notifier)
        .renameOperation(operation.id, name);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content:
            Text(ok ? 'Renamed to "$name"' : 'Could not rename that item.'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _deleteOperation(OperationFolder operation) async {
    final confirmed = await FileActions.confirmDelete(
      context,
      title: 'Delete this operation?',
      message: '"${operation.displayName}" and its ${operation.itemCount} '
          'file(s) will be removed from this app.',
    );
    if (!confirmed) return;
    await ref
        .read(operationLibraryProvider.notifier)
        .deleteOperation(operation.id);
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final library = ref.watch(operationLibraryProvider);
    final operations = _visibleOperations(library);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(theme, library),
            _buildSearchField(theme),
            if (library.isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: LinearProgressIndicator(minHeight: 2),
              ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => ref
                    .read(operationLibraryProvider.notifier)
                    .reload(pruneMissing: true),
                child: operations.isEmpty
                    ? _buildEmptyState(theme)
                    : _gridView
                        ? _buildGrid(theme, operations)
                        : _buildList(theme, operations),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _isSelecting
          ? SelectionActionBar(
              actions: [
                SelectionAction(
                  icon: Icons.share_outlined,
                  label: 'Share',
                  onTap: _busy
                      ? null
                      : () => _run((items) => FileActions.share(
                            context,
                            _filesForOperations(items),
                          )),
                ),
                SelectionAction(
                  icon: Icons.picture_as_pdf_outlined,
                  label: 'Save as PDF',
                  onTap: _busy
                      ? null
                      : () => _run((items) => FileActions.saveAsPdf(
                            context,
                            _filesForOperations(items),
                            defaultName: items.length == 1
                                ? items.first.displayName
                                : 'PixelTools_Export',
                          )),
                ),
                SelectionAction(
                  icon: Icons.download_outlined,
                  label: 'Save',
                  onTap: _busy
                      ? null
                      : () => _run((items) => FileActions.save(
                            context,
                            _filesForOperations(items),
                            defaultPdfName: items.length == 1
                                ? items.first.displayName
                                : 'PixelTools_Export',
                          )),
                ),
                if (_selected.length == 1)
                  SelectionAction(
                    icon: Icons.drive_file_rename_outline,
                    label: 'Rename',
                    onTap: _busy
                        ? null
                        : () {
                            final ops = _selectedOperations();
                            if (ops.isNotEmpty) _renameOperation(ops.first);
                          },
                  ),
                SelectionAction(
                  icon: Icons.delete_outline,
                  label: 'Delete',
                  destructive: true,
                  onTap: _busy ? null : _deleteSelected,
                ),
              ],
            )
          : null,
    );
  }

  Widget _buildHeader(ThemeData theme, OperationLibrary library) {
    final scheme = theme.colorScheme;
    final total = library.operations.length;

    // The title shrinks and the actions use compact density so the header
    // never overflows on a 320 dp phone.
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 4, 0),
      child: Row(
        children: [
          // `All (92) ▾` filter control from the reference.
          Expanded(
            child: PopupMenuButton<FileFilter>(
              tooltip: 'Filter files',
              initialValue: _filter,
              onSelected: (value) => setState(() => _filter = value),
              itemBuilder: (context) => [
                for (final filter in FileFilter.values)
                  PopupMenuItem(
                    value: filter,
                    child: Text(
                      '${filter.label} (${_countFor(filter)})',
                    ),
                  ),
              ],
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      '${_filter.label} ($total)',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                      ),
                    ),
                  ),
                  Icon(Icons.arrow_drop_down_rounded, color: scheme.onSurface),
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: 'Sort',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.sort_rounded),
            onPressed: _showSortMenu,
          ),
          IconButton(
            tooltip: _gridView ? 'List view' : 'Grid view',
            visualDensity: VisualDensity.compact,
            icon: Icon(
              _gridView ? Icons.view_list_rounded : Icons.grid_view_rounded,
            ),
            onPressed: () => setState(() => _gridView = !_gridView),
          ),
          IconButton(
            tooltip: _isSelecting ? 'Clear selection' : 'Select items',
            visualDensity: VisualDensity.compact,
            icon: Icon(
              _isSelecting
                  ? Icons.check_box_rounded
                  : Icons.check_box_outline_blank_rounded,
            ),
            onPressed: () {
              if (_isSelecting) {
                _clearSelection();
              } else {
                setState(() {
                  _selected.addAll(
                    _visibleOperations(ref.read(operationLibraryProvider))
                        .map((operation) => operation.id),
                  );
                });
              }
            },
          ),
        ],
      ),
    );
  }

  void _showSortMenu() {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;
    showMenu<FileSortOrder>(
      context: context,
      position: RelativeRect.fromLTRB(overlay.size.width - 8, 120, 8, 0),
      items: [
        for (final order in FileSortOrder.values)
          PopupMenuItem(
            value: order,
            child: Row(
              children: [
                if (order == _sort)
                  const Icon(Icons.check_rounded, size: 18)
                else
                  const SizedBox(width: 18),
                const SizedBox(width: 8),
                Text(order.label),
              ],
            ),
          ),
      ],
    ).then((value) {
      if (value != null && mounted) setState(() => _sort = value);
    });
  }

  int _countFor(FileFilter filter) {
    return ref
        .read(operationStoreProvider)
        .queryOperations(filter: filter)
        .length;
  }

  Widget _buildSearchField(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: TextField(
        controller: _searchController,
        onChanged: _onSearchChanged,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Search files and operations',
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: _searchController.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear search',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () {
                    _searchController.clear();
                    _searchDebounce?.cancel();
                    setState(() => _query = '');
                  },
                ),
          filled: true,
          fillColor: theme.colorScheme.surfaceContainerHighest,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 4),
        ),
      ),
    );
  }

  Widget _buildList(ThemeData theme, List<OperationFolder> operations) {
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
      itemCount: operations.length,
      separatorBuilder: (_, __) => Divider(
        height: 1,
        color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
      ),
      itemBuilder: (context, index) {
        final operation = operations[index];
        return _OperationRow(
          operation: operation,
          thumbnailPath: _thumbnailFor(operation),
          selected: _selected.contains(operation.id),
          onTap: () => _isSelecting
              ? _toggleSelection(operation.id)
              : _openOperation(operation),
          onLongPress: () => _toggleSelection(operation.id),
          onToggleSelected: () => _toggleSelection(operation.id),
          onRename: () => _renameOperation(operation),
          onShare: () => FileActions.share(context, _filesOf(operation.id)),
          onDelete: () => _deleteOperation(operation),
        );
      },
    );
  }

  Widget _buildGrid(ThemeData theme, List<OperationFolder> operations) {
    return GridView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 200,
        crossAxisSpacing: 12,
        mainAxisSpacing: 14,
        childAspectRatio: 0.82,
      ),
      itemCount: operations.length,
      itemBuilder: (context, index) {
        final operation = operations[index];
        return _OperationCard(
          operation: operation,
          thumbnailPath: _thumbnailFor(operation),
          selected: _selected.contains(operation.id),
          onTap: () => _isSelecting
              ? _toggleSelection(operation.id)
              : _openOperation(operation),
          onLongPress: () => _toggleSelection(operation.id),
        );
      },
    );
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

  Widget _buildEmptyState(ThemeData theme) {
    final scheme = theme.colorScheme;
    final searching = _query.trim().isNotEmpty;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(height: MediaQuery.sizeOf(context).height * 0.10),
        Icon(
          searching ? Icons.search_off_rounded : Icons.folder_open_outlined,
          size: 64,
          color: scheme.onSurfaceVariant,
        ),
        const SizedBox(height: 16),
        Center(
          child: Text(
            searching ? 'No files match "$_query"' : 'No files yet',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Text(
            searching
                ? 'Try a different name, extension or operation.'
                : 'Your processed images and PDFs will appear here, grouped by '
                    'the tool that created them.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class _OperationRow extends StatelessWidget {
  const _OperationRow({
    required this.operation,
    required this.thumbnailPath,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
    required this.onToggleSelected,
    required this.onRename,
    required this.onShare,
    required this.onDelete,
  });

  final OperationFolder operation;
  final String? thumbnailPath;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onToggleSelected;
  final VoidCallback onRename;
  final VoidCallback onShare;
  final VoidCallback onDelete;

  static bool looksLikePdf(OperationFolder operation, [String? path]) {
    if (path != null && path.isNotEmpty) {
      return path.toLowerCase().endsWith('.pdf');
    }
    return operation.kind == OperationKind.imageToPdf ||
        operation.kind == OperationKind.pdfMerge ||
        operation.kind == OperationKind.pdfSplit ||
        operation.kind == OperationKind.pdfCompress;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dateLabel =
        DateFormat('MM/dd/yyyy HH:mm').format(operation.createdAt);

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        color:
            selected ? scheme.secondaryContainer.withValues(alpha: 0.35) : null,
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            FileThumbnail(
              key: ValueKey('${operation.id}_${operation.modifiedAt.millisecondsSinceEpoch}'),
              path: thumbnailPath ?? '',
              isPdf: looksLikePdf(operation, thumbnailPath),
              size: 56,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    operation.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          dateLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(
                        Icons.description_outlined,
                        size: 13,
                        color: scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '${operation.itemCount}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      if (operation.isIncomplete) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: scheme.errorContainer,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            operation.status.name,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: scheme.onErrorContainer,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              tooltip: 'Actions',
              icon: Icon(
                Icons.more_vert_rounded,
                color: scheme.onSurfaceVariant,
              ),
              onSelected: (value) {
                switch (value) {
                  case 'open':
                    onTap();
                    break;
                  case 'rename':
                    onRename();
                    break;
                  case 'share':
                    onShare();
                    break;
                  case 'delete':
                    onDelete();
                    break;
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'open', child: Text('Open')),
                PopupMenuItem(value: 'rename', child: Text('Rename')),
                PopupMenuItem(value: 'share', child: Text('Share')),
                PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
            Checkbox(
              value: selected,
              onChanged: (_) => onToggleSelected(),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OperationCard extends StatelessWidget {
  const _OperationCard({
    required this.operation,
    required this.thumbnailPath,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
  });

  final OperationFolder operation;
  final String? thumbnailPath;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color:
                            selected ? scheme.secondary : scheme.outlineVariant,
                        width: selected ? 3 : 1,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(3),
                      child: FileThumbnail(
                        key: ValueKey('${operation.id}_${operation.modifiedAt.millisecondsSinceEpoch}'),
                        path: thumbnailPath ?? '',
                        isPdf: _OperationRow.looksLikePdf(
                            operation, thumbnailPath),
                        size: 180,
                        borderRadius: 10,
                      ),
                    ),
                  ),
                ),
                if (selected)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: scheme.secondary,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Icon(
                        Icons.check_rounded,
                        size: 16,
                        color: scheme.onSecondary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            operation.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            '${operation.itemCount} file(s)',
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
