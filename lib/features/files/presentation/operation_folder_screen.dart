import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as path;
import 'package:share_plus/share_plus.dart';

import '../../../core/models/operation_folder.dart';
import '../../../core/services/output_saver.dart';
import '../../../core/services/pdf_service.dart';
import '../../../core/services/public_storage.dart';
import '../../../core/utils/file_type_detector.dart';
import '../../collage_builder/notifiers/collage_notifier.dart';
import '../notifiers/operation_library_notifier.dart';
import '../services/file_actions.dart';
import '../widgets/file_edit_sheet.dart';
import '../widgets/file_thumbnail.dart';
import '../widgets/move_copy_dialog.dart';
import '../widgets/operation_tags_dialog.dart';

/// Contents of one operation folder: every file a single tool run produced.
///
/// Fully matches the `prev.jpg` (normal viewing & AI tools) and `prev1.jpg`
/// (selection mode & batch actions) visual designs and features.
class OperationFolderScreen extends ConsumerStatefulWidget {
  const OperationFolderScreen({super.key, required this.operationId});

  final String operationId;

  @override
  ConsumerState<OperationFolderScreen> createState() =>
      _OperationFolderScreenState();
}

class _OperationFolderScreenState extends ConsumerState<OperationFolderScreen> {
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

  void _selectAll(List<AppFileItem> files) {
    setState(() {
      if (_selected.length == files.length) {
        _selected.clear();
      } else {
        _selected
          ..clear()
          ..addAll(files.map((f) => f.id));
      }
    });
  }

  List<AppFileItem> _filesOf(OperationLibrary library) {
    return library.files
        .where((file) => file.operationId == widget.operationId)
        .toList();
  }

  List<AppFileItem> _selectedItems(List<AppFileItem> allFiles) {
    return allFiles.where((file) => _selected.contains(file.id)).toList();
  }

  Future<void> _run(Future<void> Function(List<AppFileItem> items) action,
      List<AppFileItem> files) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action(_selectedItems(files));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteSelected(List<AppFileItem> files) async {
    final items = _selectedItems(files);
    if (items.isEmpty) return;
    final confirmed = await FileActions.confirmDelete(
      context,
      title: items.length == 1
          ? 'Delete this file?'
          : 'Delete ${items.length} files?',
      message: 'The selected file(s) will be removed from this folder. '
          'Copies you saved to the gallery are not affected.',
    );
    if (!confirmed) return;
    await _run((items) async {
      await ref
          .read(operationLibraryProvider.notifier)
          .deleteFiles(items.map((item) => item.id));
    }, files);
    _clearSelection();
  }

  Future<void> _renameOperation(OperationFolder operation) async {
    final name = await FileActions.promptForName(
      context,
      title: 'Rename Folder',
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
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _deleteOperation(OperationFolder operation) async {
    final confirmed = await FileActions.confirmDelete(
      context,
      title: 'Delete this folder?',
      message:
          'This removes "${operation.displayName}" and its ${operation.itemCount} '
          'file(s) from the app. Copies saved to the gallery are not affected.',
    );
    if (!confirmed) return;
    await ref.read(operationLibraryProvider.notifier).deleteOperation(operation.id);
    if (mounted) Navigator.of(context).maybePop();
  }

  Future<void> _createPdfFromItems(List<AppFileItem> items) async {
    if (items.isEmpty) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      messenger.showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
              SizedBox(width: 12),
              Text('Creating PDF from selected images...'),
            ],
          ),
          duration: Duration(seconds: 10),
          behavior: SnackBarBehavior.floating,
        ),
      );

      final validPaths = items
          .map((item) => item.path)
          .where((p) => p.isNotEmpty && File(p).existsSync())
          .toList();

      if (validPaths.isEmpty) {
        messenger.hideCurrentSnackBar();
        if (mounted) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text('No readable files selected.'),
              behavior: SnackBarBehavior.floating,
              duration: Duration(seconds: 2),
            ),
          );
        }
        return;
      }

      final outPath = await PdfService.instance.createPdfFromMixedItems(
        paths: validPaths,
        outputBaseName: 'document',
      );

      final saved = await saveToolOutputs(
        ref.read(operationStoreProvider),
        kind: OperationKind.imageToPdf,
        entries: [
          OutputEntry.file(
            sourcePath: outPath,
            fileName: path.basename(outPath),
            publicKind: PublicFileKind.document,
          ),
        ],
      );

      await ref.read(operationLibraryProvider.notifier).reload();
      messenger.clearSnackBars();

      if (mounted) {
        final controller = messenger.showSnackBar(
          SnackBar(
            content: const Text('PDF created successfully'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
            action: saved.isNotEmpty
                ? SnackBarAction(
                    label: 'Share',
                    onPressed: () {
                      Share.shareXFiles([XFile(saved.first.localPath)]);
                    },
                  )
                : null,
          ),
        );
        Future.delayed(const Duration(seconds: 2), () {
          try {
            controller.close();
          } catch (_) {}
        });
        _clearSelection();
      }
    } catch (e) {
      messenger.clearSnackBars();
      if (mounted) {
        final errController = messenger.showSnackBar(
          SnackBar(
            content: Text('Could not create PDF: $e'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
        Future.delayed(const Duration(seconds: 2), () {
          try {
            errController.close();
          } catch (_) {}
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _makeCollageFromItems(List<AppFileItem> items) async {
    if (items.isEmpty) return;

    final imageItems = items
        .where((f) =>
            FileTypeDetector.detect(path: f.path, name: f.fileName).isImage)
        .toList();

    if (imageItems.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Collage only supports image files (JPG, PNG, WEBP). Non-image files cannot be included.',
            ),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
      return;
    }

    if (imageItems.length < items.length) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Collage only supports image files. Non-image files were excluded.',
            ),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }

    final paths = imageItems.map((f) => f.path).toList();
    await ref.read(collageProvider.notifier).loadFromPaths(paths);
    if (mounted) {
      context.push('/images/collage');
    }
  }

  Future<void> _openMoveCopy(List<AppFileItem> files) async {
    final selected = _selectedItems(files);
    if (selected.isEmpty) return;
    final success = await MoveCopyDialog.show(
      context,
      fileIds: selected.map((f) => f.id).toList(),
      currentOperationId: widget.operationId,
    );
    if (success == true) {
      _clearSelection();
    }
  }

  Future<void> _editSingleItem(AppFileItem item) async {
    await FileEditSheet.show(
      context,
      item: item,
      onDeleted: () => _selected.remove(item.id),
    );
  }

  void _onReorder(int oldIndex, int newIndex, List<AppFileItem> files) {
    if (oldIndex == newIndex) return;
    if (newIndex > oldIndex) newIndex -= 1;
    final reordered = List<AppFileItem>.from(files);
    final movedItem = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, movedItem);

    ref
        .read(operationLibraryProvider.notifier)
        .reorderFiles(widget.operationId, reordered.map((f) => f.id).toList());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final library = ref.watch(operationLibraryProvider);
    final operation = _findOperation(library);
    final files = _filesOf(library);

    if (operation == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.folder_off_outlined,
                    size: 56, color: Colors.white54),
                const SizedBox(height: 16),
                Text(
                  'This folder is no longer available.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF141414) : theme.colorScheme.surface,
      appBar: _isSelecting
          ? _buildSelectionAppBar(files)
          : _buildNormalAppBar(operation, files),
      body: SafeArea(
        child: files.isEmpty
            ? _buildEmpty(operation)
            : Column(
                children: [
                  if (_isSelecting)
                    _buildReorderBanner()
                  else
                    _buildHintBanner(),
                  Expanded(
                    child: _isSelecting
                        ? _buildReorderableGrid(files)
                        : _buildNormalGrid(files),
                  ),
                ],
              ),
      ),
      bottomNavigationBar: _isSelecting ? _buildSelectionBottomBar(files) : null,
    );
  }

  PreferredSizeWidget _buildNormalAppBar(
      OperationFolder operation, List<AppFileItem> files) {
    final title = operation.displayName;
    final tags = operation.tags;

    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        tooltip: 'Back',
        onPressed: () => Navigator.of(context).maybePop(),
      ),
      titleSpacing: 0,
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () => _renameOperation(operation),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.edit_outlined, size: 16, color: Colors.white70),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Tags + Button chip (as seen in prev.jpg)
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => OperationTagsDialog.show(context, operation: operation),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white24),
                borderRadius: BorderRadius.circular(8),
                color: tags.isNotEmpty
                    ? const Color(0xFF00E5FF).withValues(alpha: 0.15)
                    : Colors.white.withValues(alpha: 0.05),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    tags.isEmpty ? 'Tags +' : 'Tags (${tags.length})',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: tags.isNotEmpty
                          ? const Color(0xFF00E5FF)
                          : Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      actions: [
        // Collage action icon
        IconButton(
          tooltip: 'Make Collage',
          icon: const Icon(Icons.dashboard_customize_outlined),
          onPressed: files.isEmpty ? null : () => _makeCollageFromItems(files),
        ),

        // Overflow menu
        PopupMenuButton<String>(
          tooltip: 'More actions',
          icon: const Icon(Icons.more_vert_rounded),
          onSelected: (value) {
            switch (value) {
              case 'select':
                setState(() {
                  if (files.isNotEmpty) _selected.add(files.first.id);
                });
                break;
              case 'share':
                FileActions.share(context, files);
                break;
              case 'save':
                FileActions.save(context, files);
                break;
              case 'pdf':
                _createPdfFromItems(files);
                break;
              case 'collage':
                _makeCollageFromItems(files);
                break;
              case 'rename':
                _renameOperation(operation);
                break;
              case 'delete':
                _deleteOperation(operation);
                break;
            }
          },
          itemBuilder: (context) => const [
            PopupMenuItem(value: 'select', child: Text('Select items')),
            PopupMenuItem(value: 'share', child: Text('Share all')),
            PopupMenuItem(value: 'save', child: Text('Save all to Gallery')),
            PopupMenuItem(value: 'pdf', child: Text('Create PDF from all')),
            PopupMenuItem(value: 'collage', child: Text('Make Collage')),
            PopupMenuItem(value: 'rename', child: Text('Rename folder')),
            PopupMenuItem(value: 'delete', child: Text('Delete folder')),
          ],
        ),
      ],
    );
  }

  PreferredSizeWidget _buildSelectionAppBar(List<AppFileItem> files) {
    final count = _selected.length;
    final allSelected = count == files.length && files.isNotEmpty;

    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        tooltip: 'Cancel selection',
        onPressed: _clearSelection,
      ),
      title: Text(
        '$count selected',
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      actions: [
        TextButton(
          onPressed: () => _selectAll(files),
          child: Text(
            allSelected ? 'Deselect All' : 'Select All',
            style: const TextStyle(
              color: Color(0xFF00E5FF),
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildReorderBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.white.withValues(alpha: 0.04),
      child: const Row(
        children: [
          Icon(Icons.info_outline_rounded, size: 16, color: Colors.white60),
          SizedBox(width: 8),
          Text(
            'Hold and drag to reorder',
            style: TextStyle(fontSize: 12, color: Colors.white70),
          ),
        ],
      ),
    );
  }

  Widget _buildHintBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.white.withValues(alpha: 0.03),
      child: const Row(
        children: [
          Icon(Icons.info_outline_rounded, size: 15, color: Colors.white60),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Tap to open · hold to select',
              style: TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNormalGrid(List<AppFileItem> files) {
    // 2 columns grid matching `prev.jpg`
    // Includes images + the promotional "Try making a collage" card
    final totalCards = files.length + 1; // +1 for collage card

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 14,
        mainAxisSpacing: 16,
        childAspectRatio: 0.72,
      ),
      itemCount: totalCards,
      itemBuilder: (context, index) {
        if (index < files.length) {
          final item = files[index];
          return _DocumentPageTile(
            item: item,
            index: index,
            isSelected: false,
            isSelecting: false,
            onTap: () => _editSingleItem(item),
            onLongPress: () => _toggle(item),
            onCheckboxTap: () => _toggle(item),
          );
        } else {
          // "Try making a collage" Card (matching `prev.jpg`)
          return _CollagePromoTile(
            onTap: () => _makeCollageFromItems(files),
          );
        }
      },
    );
  }

  Widget _buildReorderableGrid(List<AppFileItem> files) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 14,
        mainAxisSpacing: 16,
        childAspectRatio: 0.72,
      ),
      itemCount: files.length,
      itemBuilder: (context, index) {
        final item = files[index];
        final selected = _selected.contains(item.id);
        return LongPressDraggable<int>(
          data: index,
          feedback: Material(
            color: Colors.transparent,
            child: SizedBox(
              width: 160,
              height: 220,
              child: _DocumentPageTile(
                item: item,
                index: index,
                isSelected: selected,
                isSelecting: true,
                onTap: () {},
                onLongPress: () {},
                onCheckboxTap: () {},
              ),
            ),
          ),
          childWhenDragging: Opacity(
            opacity: 0.3,
            child: _DocumentPageTile(
              item: item,
              index: index,
              isSelected: selected,
              isSelecting: true,
              onTap: () => _toggle(item),
              onLongPress: () => _toggle(item),
              onCheckboxTap: () => _toggle(item),
            ),
          ),
          child: DragTarget<int>(
            onAcceptWithDetails: (details) =>
                _onReorder(details.data, index, files),
            builder: (context, candidateData, rejectedData) {
              return _DocumentPageTile(
                item: item,
                index: index,
                isSelected: selected,
                isSelecting: true,
                onTap: () => _toggle(item),
                onLongPress: () => _toggle(item),
                onCheckboxTap: () => _toggle(item),
              );
            },
          ),
        );
      },
    );
  }



  Widget _buildSelectionBottomBar(List<AppFileItem> files) {
    final selectedCount = _selected.length;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF181B20) : scheme.surfaceContainerHighest,
          border: Border(
            top: BorderSide(
              color: isDark
                  ? Colors.white12
                  : scheme.outlineVariant.withValues(alpha: 0.3),
            ),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _SelectionBarItem(
              icon: Icons.share_outlined,
              label: 'Share',
              onTap: _busy
                  ? null
                  : () => _run((items) => FileActions.share(context, items), files),
            ),
            _SelectionBarItem(
              icon: Icons.download_outlined,
              label: 'Save',
              onTap: _busy
                  ? null
                  : () => _run((items) => FileActions.save(context, items), files),
            ),
            _SelectionBarItem(
              icon: Icons.drive_file_move_outlined,
              label: 'Move/Copy',
              onTap: _busy ? null : () => _openMoveCopy(files),
            ),
            _SelectionBarItem(
              icon: Icons.dashboard_customize_outlined,
              label: 'Collage',
              badge: true,
              onTap: _busy ? null : () => _makeCollageFromItems(_selectedItems(files)),
            ),
            _SelectionBarItem(
              icon: Icons.picture_as_pdf_outlined,
              label: 'Create PDF',
              onTap: _busy ? null : () => _createPdfFromItems(_selectedItems(files)),
            ),
            if (selectedCount == 1)
              _SelectionBarItem(
                icon: Icons.tune_rounded,
                label: 'Edit',
                onTap: _busy
                    ? null
                    : () => _editSingleItem(_selectedItems(files).first),
              ),
            _SelectionBarItem(
              icon: Icons.delete_outline,
              label: 'Delete',
              isDestructive: true,
              onTap: _busy ? null : () => _deleteSelected(files),
            ),
          ],
        ),
      ),
    );
  }

  OperationFolder? _findOperation(OperationLibrary library) {
    for (final candidate in library.operations) {
      if (candidate.id == widget.operationId) return candidate;
    }
    return null;
  }

  Widget _buildEmpty(OperationFolder operation) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.folder_open_outlined,
                size: 56, color: Colors.white54),
            const SizedBox(height: 16),
            Text(
              operation.status == OperationStatus.completed
                  ? 'This folder has no files.'
                  : 'This operation did not finish.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }
}

/// A document/image tile matching `prev.jpg` and `prev1.jpg`.
class _DocumentPageTile extends StatelessWidget {
  const _DocumentPageTile({
    required this.item,
    required this.index,
    required this.isSelected,
    required this.isSelecting,
    required this.onTap,
    required this.onLongPress,
    required this.onCheckboxTap,
  });

  final AppFileItem item;
  final int index;
  final bool isSelected;
  final bool isSelecting;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onCheckboxTap;

  @override
  Widget build(BuildContext context) {
    final pageNumber = (index + 1).toString().padLeft(2, '0');

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Image / Page Card
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected
                            ? const Color(0xFF00E5FF)
                            : Colors.white12,
                        width: isSelected ? 2.5 : 1.0,
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: FileThumbnail(
                      path: item.path,
                      isPdf: item.isPdf,
                      size: 260,
                      borderRadius: 8,
                    ),
                  ),
                ),

                // Selection checkbox (shown in selection mode matching `prev1.jpg`)
                if (isSelecting)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: GestureDetector(
                      onTap: onCheckboxTap,
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFF00E5FF)
                              : Colors.black45,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: isSelected
                                ? const Color(0xFF00E5FF)
                                : Colors.white60,
                            width: 1.5,
                          ),
                        ),
                        child: isSelected
                            ? const Icon(
                                Icons.check_rounded,
                                size: 16,
                                color: Colors.black,
                              )
                            : null,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // Centered page index badge below card (matching `prev.jpg` & `prev1.jpg`)
          Center(
            child: isSelected
                ? Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00E5FF),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      pageNumber,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: Colors.black,
                      ),
                    ),
                  )
                : Text(
                    pageNumber,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// "Try making a collage" card matching `prev.jpg`.
class _CollagePromoTile extends StatelessWidget {
  const _CollagePromoTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1B1D22),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white10),
              ),
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'Try making a collage',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.white70,
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Mockup of collage document with "A4" watermark
                  Container(
                    width: 90,
                    height: 120,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 6,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(6),
                    child: Stack(
                      children: [
                        Column(
                          children: [
                            Container(
                              height: 24,
                              decoration: BoxDecoration(
                                color: Colors.blue.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(2),
                              ),
                              child: const Center(
                                child: Text(
                                  'TAX',
                                  style: TextStyle(
                                    fontSize: 8,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              height: 24,
                              decoration: BoxDecoration(
                                color: Colors.green.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(2),
                              ),
                              child: const Center(
                                child: Text(
                                  'TAX',
                                  style: TextStyle(
                                    fontSize: 8,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              height: 24,
                              decoration: BoxDecoration(
                                color: Colors.orange.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(2),
                              ),
                              child: const Center(
                                child: Text(
                                  'TAX',
                                  style: TextStyle(
                                    fontSize: 8,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.orange,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const Positioned(
                          right: 2,
                          bottom: 2,
                          child: Text(
                            'A4',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: Colors.black54,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Center(
            child: SizedBox(height: 20), // Placeholder to match page number spacing
          ),
        ],
      ),
    );
  }
}

class _SelectionBarItem extends StatelessWidget {
  const _SelectionBarItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.badge = false,
    this.isDestructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool badge;
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final enabled = onTap != null;
    final color = !enabled
        ? (isDark ? Colors.white24 : scheme.onSurface.withValues(alpha: 0.38))
        : isDestructive
            ? (isDark ? const Color(0xFFFF5252) : scheme.error)
            : (isDark ? Colors.white : scheme.onSurface);

    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(icon, size: 21, color: color),
                  if (badge)
                    Positioned(
                      top: -4,
                      right: -4,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(
                          color: Color(0xFFFFB300),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.star,
                          size: 8,
                          color: Colors.black,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
