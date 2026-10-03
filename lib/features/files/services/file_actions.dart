import 'dart:io';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/models/operation_folder.dart';
import '../../../core/services/pdf_service.dart';
import '../../../core/services/private_to_public_pdf_manager.dart';
import '../../../core/services/public_storage.dart';

/// Shared file actions used by Files and the folder-content screen, so the
/// behaviour (and the error messages) stay identical everywhere.
abstract final class FileActions {
  /// Shares any number of files through the platform share sheet.
  static Future<void> share(
    BuildContext context,
    List<AppFileItem> items,
  ) async {
    final existing = items
        .map((item) => item.path)
        .where((path) => path.isNotEmpty && File(path).existsSync())
        .toList();
    // Capture the messenger up front: the widget may be gone by the time the
    // share sheet closes.
    final messenger = ScaffoldMessenger.of(context);
    if (existing.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Those files are no longer available.'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    try {
      await Share.shareXFiles(
        existing.map(XFile.new).toList(),
        subject: items.length == 1 ? items.first.fileName : null,
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Could not share those files.'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  /// Copies image files into the device gallery / Pictures folder.
  ///
  /// Only app-owned files are copied; deleting an app file never removes it
  /// from the gallery.
  static Future<void> saveToGallery(
    BuildContext context,
    List<AppFileItem> items,
  ) async {
    final images = items.where((item) => item.isImage).toList();
    if (images.isEmpty) {
      _message(context, 'Only images can be saved to the gallery.');
      return;
    }

    var saved = 0;
    var failed = 0;
    for (final item in images) {
      try {
        final file = File(item.path);
        if (!await file.exists()) {
          failed++;
          continue;
        }
        await PublicStorage.publishFile(
          sourcePath: item.path,
          fileName: item.fileName,
          kind: PublicFileKind.image,
        );
        saved++;
      } catch (_) {
        failed++;
      }
    }

    if (!context.mounted) return;
    if (saved > 0 && failed == 0) {
      _message(
        context,
        saved == 1
            ? 'Saved 1 image to the gallery.'
            : 'Saved $saved images to the gallery.',
      );
    } else if (saved > 0) {
      _message(context, 'Saved $saved image(s); $failed could not be saved.');
    } else {
      _message(context, 'Could not save to the gallery.');
    }
  }

  /// Exports PDFs through the system save dialog.
  /// When exporting 1 PDF, prompts for save file location.
  /// When exporting multiple PDFs, exports to a folder once via SAF (no repeated prompts).
  static Future<void> exportPdfs(
    BuildContext context,
    List<AppFileItem> items,
  ) async {
    final pdfs = items.where((item) => item.isPdf).toList();
    if (pdfs.isEmpty) {
      _message(context, 'There are no PDFs to export.');
      return;
    }

    if (pdfs.length == 1) {
      final result = await PrivateToPublicPdfManager().exportSingleFile(
        sandboxPath: pdfs.first.path,
        suggestedName: pdfs.first.fileName,
      );
      if (!context.mounted) return;
      _message(
        context,
        result == null ? 'Export cancelled.' : 'Exported 1 PDF file(s).',
      );
      return;
    }

    // Multiple PDFs: export together into a selected folder with a single folder prompt
    final results = await PrivateToPublicPdfManager().exportMultipleFiles(
      sandboxPaths: pdfs.map((item) => item.path).toList(),
      nameOverride: (index, _) => pdfs[index].fileName,
    );

    if (!context.mounted) return;
    _message(
      context,
      results.isEmpty
          ? 'Export cancelled.'
          : 'Exported ${results.length} PDF file(s).',
    );
  }

  /// Saves all items (images and/or PDFs) into a single consolidated multi-page PDF document.
  /// For PDFs, all pages are preserved and merged. For images, each image is added as a page.
  static Future<void> saveAsPdf(
    BuildContext context,
    List<AppFileItem> items, {
    String? defaultName,
  }) async {
    final validPaths = items
        .map((item) => item.path)
        .where((p) => p.isNotEmpty && File(p).existsSync())
        .toList();

    if (validPaths.isEmpty) {
      _message(context, 'No valid files to convert to PDF.');
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
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
            Text('Generating PDF document...'),
          ],
        ),
        duration: Duration(seconds: 10),
        behavior: SnackBarBehavior.floating,
      ),
    );

    try {
      final cleanDefault = defaultName ??
          (items.isNotEmpty
              ? items.first.fileName.replaceAll(RegExp(r'\.[^\.]+$'), '')
              : 'PixelTools_Export');
      final outPath = await PdfService.instance.createPdfFromMixedItems(
        paths: validPaths,
        outputBaseName: cleanDefault,
      );

      messenger.clearSnackBars();
      final result = await PrivateToPublicPdfManager().exportSingleFile(
        sandboxPath: outPath,
        suggestedName: '$cleanDefault.pdf',
      );

      if (!context.mounted) return;
      if (result != null) {
        _message(context, 'PDF saved successfully.');
      } else {
        _message(context, 'Export cancelled.');
      }
    } catch (e) {
      messenger.clearSnackBars();
      if (context.mounted) {
        _message(context, 'Could not create PDF: $e');
      }
    }
  }

  /// Comprehensive save modal bottom sheet for multi-folder or directory selection.
  /// Offers saving as a single consolidated PDF, saving images to gallery, or exporting all files.
  static Future<void> showSaveOptions(
    BuildContext context,
    List<AppFileItem> items, {
    String? defaultPdfName,
  }) async {
    final hasImages = items.any((i) => i.isImage);
    final hasPdfs = items.any((i) => i.isPdf);
    final totalCount = items.length;

    if (totalCount == 0) return;

    // Single image shortcut
    if (hasImages && !hasPdfs && totalCount == 1) {
      await saveToGallery(context, items);
      return;
    }
    // Single PDF shortcut
    if (hasPdfs && !hasImages && totalCount == 1) {
      await exportPdfs(context, items);
      return;
    }

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Row(
                    children: [
                      Icon(Icons.download_rounded, color: scheme.primary),
                      const SizedBox(width: 10),
                      Text(
                        'Save Options ($totalCount file${totalCount == 1 ? '' : 's'})',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.picture_as_pdf_rounded, color: Colors.redAccent),
                  title: const Text('Save as Single PDF'),
                  subtitle: const Text('Merge all pages and images into one document'),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    saveAsPdf(context, items, defaultName: defaultPdfName);
                  },
                ),
                if (hasImages)
                  ListTile(
                    leading: const Icon(Icons.photo_library_outlined, color: Colors.blueAccent),
                    title: const Text('Save Images to Gallery'),
                    subtitle: const Text('Save photos directly to device gallery'),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      saveToGallery(context, items);
                    },
                  ),
                ListTile(
                  leading: const Icon(Icons.drive_folder_upload_outlined, color: Colors.amber),
                  title: const Text('Export Files to Folder'),
                  subtitle: const Text('Choose a folder to save all files once'),
                  onTap: () async {
                    Navigator.of(sheetContext).pop();
                    if (hasPdfs) {
                      await exportPdfs(context, items);
                    }
                    if (hasImages && context.mounted) {
                      await saveToGallery(context, items);
                    }
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Saves any mix of images and PDFs with the right mechanism for each.
  /// If multiple files or folders are selected, provides comprehensive save options.
  static Future<void> save(
    BuildContext context,
    List<AppFileItem> items, {
    String? defaultPdfName,
  }) async {
    final images = items.where((item) => item.isImage).toList();
    final pdfs = items.where((item) => item.isPdf).toList();

    if ((images.isNotEmpty && pdfs.isNotEmpty) || pdfs.length > 1) {
      await showSaveOptions(context, items, defaultPdfName: defaultPdfName);
      return;
    }

    if (images.isNotEmpty) await saveToGallery(context, images);
    if (pdfs.isNotEmpty && context.mounted) await exportPdfs(context, pdfs);
  }

  /// Confirmation dialog. Returns true when the user confirms.
  static Future<bool> confirmDelete(
    BuildContext context, {
    required String title,
    required String message,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  /// Prompt for a new name. Returns null when cancelled.
  static Future<String?> promptForName(
    BuildContext context, {
    required String title,
    required String initialValue,
    String label = 'Name',
  }) {
    return showDialog<String>(
      context: context,
      builder: (_) => _PromptForNameDialog(
        title: title,
        initialValue: initialValue,
        label: label,
      ),
    );
  }

  static void _message(
    BuildContext context,
    String text, {
    Duration duration = const Duration(seconds: 2),
  }) {
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    final controller = messenger.showSnackBar(
      SnackBar(
        content: Text(text),
        behavior: SnackBarBehavior.floating,
        duration: duration,
      ),
    );
    Future.delayed(duration, () {
      try {
        controller.close();
      } catch (_) {}
    });
  }
}

class _PromptForNameDialog extends StatefulWidget {
  const _PromptForNameDialog({
    required this.title,
    required this.initialValue,
    required this.label,
  });

  final String title;
  final String initialValue;
  final String label;

  @override
  State<_PromptForNameDialog> createState() => _PromptForNameDialogState();
}

class _PromptForNameDialogState extends State<_PromptForNameDialog> {
  late final TextEditingController _controller;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState?.validate() == true) {
      Navigator.of(context).pop(_controller.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            labelText: widget.label,
            border: const OutlineInputBorder(),
          ),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Please enter a name';
            }
            return null;
          },
          onFieldSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
