import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/models/operation_folder.dart';
import '../../../core/services/interstitial_tracker.dart';
import '../../../core/services/operation_store_provider.dart';
import '../../../core/services/output_saver.dart';
import '../../../core/services/public_storage.dart';
import '../../../shared/models/edit_history_item.dart';
import '../../../shared/notifiers/edit_history_notifier.dart';
import '../models/collage_palette.dart';
import '../notifiers/collage_notifier.dart';
import 'collage_text_dialog.dart';

class CollageToolbar extends ConsumerStatefulWidget {
  const CollageToolbar({super.key});

  @override
  ConsumerState<CollageToolbar> createState() => _CollageToolbarState();
}

class _CollageToolbarState extends ConsumerState<CollageToolbar> {
  bool _isSharing = false;
  final GlobalKey _shareButtonKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(collageProvider);
    final scheme = Theme.of(context).colorScheme;
    final isBusy = state.isExporting || _isSharing;
    final canPerformAction = !isBusy && state.imageCount > 0;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      decoration: BoxDecoration(
        color: scheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Edit controls row
                Row(
                  children: [
                    Expanded(
                      child: _ToolbarButton(
                        icon: Icons.grid_on,
                        label: 'Gap',
                        onTap: isBusy ? null : () => _showGapSlider(context, ref),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: _ToolbarButton(
                        icon: Icons.rounded_corner,
                        label: 'Radius',
                        onTap: isBusy ? null : () => _showRadiusSlider(context, ref),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: _ToolbarButton(
                        icon: Icons.palette,
                        label: 'Color',
                        onTap: isBusy ? null : () => _showColorPicker(context, ref),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: _ToolbarButton(
                        icon: Icons.title,
                        label: 'Text',
                        onTap: isBusy ? null : () => showCollageTextDialog(context),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: _ToolbarButton(
                        icon: Icons.add_photo_alternate,
                        label: 'Add',
                        onTap: isBusy || state.imageCount >= CollageNotifier.maxCollageImages
                            ? null
                            : () {
                                ref
                                    .read(collageProvider.notifier)
                                    .pickImages(context);
                                InterstitialTracker.instance.trackAction();
                              },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // Action row
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: canPerformAction
                            ? () => _exportCollage(context, ref)
                            : null,
                        icon: (state.isExporting && !_isSharing)
                            ? SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  value: state.exportProgress > 0
                                      ? state.exportProgress
                                      : null,
                                ),
                              )
                            : const Icon(Icons.photo_library_rounded),
                        label: Text((state.isExporting && !_isSharing)
                            ? 'Saving...'
                            : 'Save to Gallery'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        key: _shareButtonKey,
                        onPressed: canPerformAction
                            ? () => _shareCollage(context, ref)
                            : null,
                        icon: _isSharing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.share),
                        label: Text(_isSharing ? 'Sharing...' : 'Share'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
            );
          },
        ),
      ),
    );
  }

  void _showGapSlider(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => Consumer(
        builder: (context, ref, _) {
          final currentGap = ref.watch(collageProvider.select((s) => s.gap));
          final theme = Theme.of(context);
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Spacing / Gap',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${currentGap.toInt()} px',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onPrimaryContainer,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final g in [0.0, 4.0, 8.0, 12.0, 16.0, 20.0])
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(g == 0 ? 'None' : '${g.toInt()}px'),
                            selected: currentGap.toInt() == g.toInt(),
                            onSelected: (_) {
                              ref.read(collageProvider.notifier).setGap(g);
                            },
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Slider(
                  value: currentGap,
                  min: 0,
                  max: 20,
                  divisions: 20,
                  onChanged: (value) {
                    ref.read(collageProvider.notifier).setGap(value);
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showRadiusSlider(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => Consumer(
        builder: (context, ref, _) {
          final currentRadius =
              ref.watch(collageProvider.select((s) => s.cornerRadius));
          final theme = Theme.of(context);
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Corner Radius',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${currentRadius.toInt()} px',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onPrimaryContainer,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final r in [0.0, 8.0, 16.0, 24.0, 36.0, 50.0])
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(r == 0 ? 'Square' : '${r.toInt()}px'),
                            selected: currentRadius.toInt() == r.toInt(),
                            onSelected: (_) {
                              ref.read(collageProvider.notifier).setCornerRadius(r);
                            },
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Slider(
                  value: currentRadius,
                  min: 0,
                  max: 50,
                  divisions: 50,
                  onChanged: (value) {
                    ref.read(collageProvider.notifier).setCornerRadius(value);
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showColorPicker(BuildContext context, WidgetRef ref) {
    final current = ref.read(collageProvider).backgroundColor;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              // Never taller than the screen; scrolls when the palette or the
              // font scale needs more room.
              maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.62,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Background Color',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final group in CollagePalette.groups) ...[
                          Text(
                            group.label,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.4,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              for (final color in group.colors)
                                _buildColorSwatch(
                                  sheetContext,
                                  ref,
                                  color,
                                  current,
                                ),
                            ],
                          ),
                          const SizedBox(height: 18),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildColorSwatch(
    BuildContext context,
    WidgetRef ref,
    Color color,
    Color current,
  ) {
    final theme = Theme.of(context);
    final selected = color == current;
    return Semantics(
      label: 'Background colour',
      button: true,
      selected: selected,
      child: Tooltip(
        message: 'Use this background',
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () {
            ref.read(collageProvider.notifier).setBackgroundColor(color);
            Navigator.pop(context);
          },
          child: Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: selected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outlineVariant,
                width: selected ? 3 : 1,
              ),
            ),
            child: selected
                ? Icon(
                    Icons.check_rounded,
                    size: 20,
                    color: CollagePalette.isLight(color)
                        ? Colors.black87
                        : Colors.white,
                  )
                : null,
          ),
        ),
      ),
    );
  }


  Future<void> _exportCollage(BuildContext context, WidgetRef ref) async {
    if (_isSharing || ref.read(collageProvider).isExporting) return;

    try {
      final bytes = await ref.read(collageProvider.notifier).exportCollage();
      if (bytes == null || bytes.isEmpty) return;

      final fileName = 'collage_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final saved = await saveToolOutputs(
        ref.read(operationStoreProvider),
        kind: OperationKind.collage,
        entries: [
          OutputEntry.bytes(
            bytes: bytes,
            fileName: fileName,
            publicKind: PublicFileKind.image,
          ),
        ],
      );

      if (context.mounted && saved.isNotEmpty) {
        final out = saved.first;
        ref.read(editHistoryProvider.notifier).addEntry(
              EditHistoryItem(
                fileName: fileName,
                toolUsed: 'Collage Builder',
                editedAt: DateTime.now(),
                toolIcon: Icons.dashboard_customize_rounded,
                filePath: out.localPath,
                thumbnailPath: out.localPath,
              ),
            );
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Saved to the gallery and Files'),
            duration: Duration(seconds: 2),
          ),
        );
        ref.read(collageProvider.notifier).reset();
        InterstitialTracker.instance.trackAction();
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _shareCollage(BuildContext context, WidgetRef ref) async {
    if (_isSharing || ref.read(collageProvider).isExporting) return;

    setState(() {
      _isSharing = true;
    });

    try {
      final bytes = await ref.read(collageProvider.notifier).exportCollage();
      if (bytes == null || bytes.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to generate collage image.')),
          );
        }
        return;
      }

      final fileName = 'collage_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final tempDir = await getTemporaryDirectory();
      final tempFile = File(path.join(tempDir.path, fileName));
      tempFile.writeAsBytesSync(bytes, flush: true);

      if (!tempFile.existsSync() || tempFile.lengthSync() == 0) {
        throw Exception('Collage image file could not be created');
      }

      Rect? sharePositionOrigin;
      final box = _shareButtonKey.currentContext?.findRenderObject() as RenderBox?;
      if (box != null && box.hasSize && box.size.width > 0 && box.size.height > 0) {
        sharePositionOrigin = box.localToGlobal(Offset.zero) & box.size;
      }
      if (sharePositionOrigin == null && context.mounted) {
        final size = MediaQuery.sizeOf(context);
        sharePositionOrigin = Rect.fromCenter(
          center: Offset(size.width / 2, size.height / 2),
          width: 1,
          height: 1,
        );
      }

      final xFile = XFile(
        tempFile.path,
        mimeType: 'image/jpeg',
        name: fileName,
      );

      try {
        await Share.shareXFiles(
          [xFile],
          subject: 'Collage created with PixelTools',
          sharePositionOrigin: sharePositionOrigin,
        );
      } on UnimplementedError catch (_) {
        if (!kIsWeb && Platform.isLinux) {
          await Process.run('xdg-open', [tempFile.path]);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Opened collage: ${tempFile.path}')),
            );
          }
        } else {
          rethrow;
        }
      }

      _cleanupOldTempCollages(tempDir, fileName);

      InterstitialTracker.instance.trackAction();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error sharing: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSharing = false;
        });
      }
    }
  }

  void _cleanupOldTempCollages(Directory tempDir, String currentFileName) {
    try {
      final list = tempDir.listSync();
      final now = DateTime.now();
      for (final entity in list) {
        if (entity is File &&
            path.basename(entity.path).startsWith('collage_') &&
            path.basename(entity.path).endsWith('.jpg') &&
            path.basename(entity.path) != currentFileName) {
          try {
            if (now.difference(entity.lastModifiedSync()).inMinutes > 15) {
              entity.deleteSync();
            }
          } catch (_) {}
        }
      }
    } catch (_) {}
  }
}

class _ToolbarButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _ToolbarButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDisabled = onTap == null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          children: [
            Icon(
              icon,
              size: 20,
              color: isDisabled
                  ? scheme.onSurfaceVariant.withValues(alpha: 0.4)
                  : null,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: isDisabled
                    ? scheme.onSurfaceVariant.withValues(alpha: 0.4)
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
