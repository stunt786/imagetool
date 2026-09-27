import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/models/operation_folder.dart';
import '../notifiers/operation_library_notifier.dart';
import '../services/file_actions.dart';
import '../services/file_open_service.dart';
import '../widgets/file_thumbnail.dart';
import '../widgets/selection_action_bar.dart';

/// Contents of one operation folder: every file a single tool run produced.
///
/// Layout follows the `prev.jpg` / `prev1.jpg` references — a numbered grid
/// with a contextual bottom action bar when items are selected.
class OperationFolderScreen extends ConsumerStatefulWidget {
  const OperationFolderScreen({super.key, required this.operationId});

  final String operationId;

  @override
  ConsumerState<OperationFolderScreen> createState() =>
      _OperationFolderScreenState();
}

class _OperationFolderScreenState
    extends ConsumerState<OperationFolderScreen> {
  final Set<String> _selected = <String>{};
  bool _busy = false;

  bool get _isSelecting => _selected.isNotEmpty;

  void _toggle(AppFileItem item) {
    setState(() {
      if (_selected.contains(item.id)) {
        _selected.remove(item.id);
      } else {
        _selected.add(item.id);
      }
    });
  }

  void _clearSelection() => setState(_selected.clear);

  void _selectAll() => setState(() {
        _selected
          ..clear()
          ..addAll(_filesOf(operationId: widget.operationId).map((f) => f.id));
      });

  List<AppFileItem> _filesOf({required String operationId}) {
    return ref
        .read(operationLibraryProvider)
        .files
        .where((file) => file.operationId == operationId)
        .toList();
  }

  List<AppFileItem> get _selectedItems {
    final all = ref.read(operationLibraryProvider).files;
    return all.where((file) => _selected.contains(file.id)).toList();
  }

  Future<void> _run(Future<void> Function(List<AppFileItem> items) action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action(_selectedItems);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteSelected() async {
    final items = _selectedItems;
    if (items.isEmpty) return;
    final confirmed = await FileActions.confirmDelete(
      context,
      title: items.length == 1 ? 'Delete this file?' : 'Delete ${items.length} files?',
      message: 'The selected file(s) will be removed from this app. '
          'Copies you saved to the gallery are not affected.',
    );
    if (!confirmed) return;
    await _run((items) async {
      await ref
          .read(operationLibraryProvider.notifier)
          .deleteFiles(items.map((item) => item.id));
    });
    _clearSelection();
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
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Renamed to "$name"'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _renameSelectedFile() async {
    final items = _selectedItems;
    if (items.length != 1) return;
    final item = items.first;
    final name = await FileActions.promptForName(
      context,
      title: 'Rename file',
      initialValue: item.fileName,
    );
    if (name == null) return;
    final ok = await ref
        .read(operationLibraryProvider.notifier)
        .renameFile(item.id, name);
    if (ok) _clearSelection();
  }

  Future<void> _deleteOperation(OperationFolder operation) async {
    final confirmed = await FileActions.confirmDelete(
      context,
      title: 'Delete this operation?',
      message:
          'This removes "${operation.displayName}" and its ${operation.itemCount} '
          'file(s) from the app. Copies saved to the gallery are not affected.',
    );
    if (!confirmed) return;
    await ref.read(operationLibraryProvider.notifier).deleteOperation(operation.id);
    if (mounted) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final library = ref.watch(operationLibraryProvider);
    final matched = _findOperation(library);
    final files = library.files
        .where((file) => file.operationId == widget.operationId)
        .toList()
      ..sort((a, b) => a.fileName.compareTo(b.fileName));

    if (matched == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.folder_off_outlined,
                    size: 56, color: scheme.onSurfaceVariant),
                const SizedBox(height: 16),
                Text(
                  'This operation is no longer available.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final OperationFolder operation = matched;

    return Scaffold(
      appBar: AppBar(
        leading: _isSelecting
            ? IconButton(
                tooltip: 'Cancel selection',
                onPressed: _clearSelection,
                icon: const Icon(Icons.close_rounded),
              )
            : null,
        title: _isSelecting
            ? Text('${_selected.length} selected')
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    operation.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    _subtitle(operation, files),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
        actions: _isSelecting
            ? [
                if (files.isNotEmpty)
                  TextButton(
                    onPressed: _selected.length == files.length
                        ? _clearSelection
                        : _selectAll,
                    child: Text(
                      _selected.length == files.length ? 'Clear all' : 'Select all',
                    ),
                  ),
              ]
            : [
                IconButton(
                  tooltip: 'Rename operation',
                  onPressed: () => _renameOperation(operation),
                  icon: const Icon(Icons.edit_outlined),
                ),
                PopupMenuButton<String>(
                  tooltip: 'More actions',
                  onSelected: (value) {
                    switch (value) {
                      case 'share':
                        FileActions.share(context, files);
                        break;
                      case 'save':
                        FileActions.save(context, files);
                        break;
                      case 'delete':
                        _deleteOperation(operation);
                        break;
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'share', child: Text('Share all')),
                    PopupMenuItem(value: 'save', child: Text('Save all')),
                    PopupMenuItem(value: 'delete', child: Text('Delete operation')),
                  ],
                ),
              ],
      ),
      body: SafeArea(
        child: files.isEmpty
            ? _buildEmpty(operation, scheme)
            : Column(
                children: [
                  if (!_isSelecting)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline_rounded,
                              size: 15, color: scheme.onSurfaceVariant),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Tap to open · hold to select',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                          ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: GridView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 220,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 18,
                        childAspectRatio: 0.78,
                      ),
                      itemCount: files.length,
                      itemBuilder: (context, index) => _FolderTile(
                        item: files[index],
                        index: index,
                        selected: _selected.contains(files[index].id),
                        onTap: () {
                          if (_isSelecting) {
                            _toggle(files[index]);
                          } else {
                            FileOpenService.open(
                              context,
                              path: files[index].path,
                              name: files[index].fileName,
                            );
                          }
                        },
                        onLongPress: () => _toggle(files[index]),
                      ),
                    ),
                  ),
                ],
              ),
      ),
      bottomNavigationBar: _isSelecting
          ? SelectionActionBar(
              count: _selected.length,
              actions: [
                SelectionAction(
                  icon: Icons.share_outlined,
                  label: 'Share',
                  onTap: _busy
                      ? null
                      : () => _run((items) => FileActions.share(context, items)),
                ),
                SelectionAction(
                  icon: Icons.download_outlined,
                  label: 'Save',
                  onTap: _busy
                      ? null
                      : () => _run((items) => FileActions.save(context, items)),
                ),
                if (_selected.length == 1)
                  SelectionAction(
                    icon: Icons.drive_file_rename_outline,
                    label: 'Rename',
                    onTap: _busy ? null : _renameSelectedFile,
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

  OperationFolder? _findOperation(OperationLibrary library) {
    for (final candidate in library.operations) {
      if (candidate.id == widget.operationId) return candidate;
    }
    return null;
  }

  String _subtitle(OperationFolder operation, List<AppFileItem> files) {
    final formatter = DateFormat('MM/dd/yyyy HH:mm');
    final count = files.isEmpty ? operation.itemCount : files.length;
    final size = files.fold<int>(0, (sum, item) => sum + item.sizeBytes);
    final sizeLabel = _formatSize(size);
    final status = operation.status == OperationStatus.completed
        ? ''
        : ' · ${operation.status.name}';
    return '${formatter.format(operation.createdAt)} · $count file(s) · $sizeLabel$status';
  }

  Widget _buildEmpty(OperationFolder operation, ColorScheme scheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.folder_open_outlined,
                size: 56, color: scheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              operation.status == OperationStatus.completed
                  ? 'This operation produced no files.'
                  : 'This operation did not finish.',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            if (operation.errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                operation.errorMessage!,
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: scheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class _FolderTile extends StatelessWidget {
  const _FolderTile({
    required this.item,
    required this.index,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
  });

  final AppFileItem item;
  final int index;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = scheme.secondary;

    return Semantics(
      selected: selected,
      button: true,
      label: item.fileName,
      child: InkWell(
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
                          color: selected ? accent : scheme.outlineVariant,
                          width: selected ? 3 : 1,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(3),
                        child: FileThumbnail(
                          path: item.path,
                          isPdf: item.isPdf,
                          size: 200,
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
                          color: accent,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Icon(Icons.check_rounded,
                            size: 16, color: scheme.onSecondary),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: selected ? accent : scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    (index + 1).toString().padLeft(2, '0'),
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: selected
                          ? scheme.onSecondary
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              item.fileName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
