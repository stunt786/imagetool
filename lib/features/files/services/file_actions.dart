import 'dart:io';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/models/operation_folder.dart';
import '../../../core/services/private_to_public_pdf_manager.dart';
import '../../../shared/utils/image_saver.dart';

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
        final bytes = await file.readAsBytes();
        await saveImageBytes(bytes, fileName: item.fileName);
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

  /// Exports PDFs through the system save dialog (one file at a time).
  static Future<void> exportPdfs(
    BuildContext context,
    List<AppFileItem> items,
  ) async {
    final pdfs = items.where((item) => item.isPdf).toList();
    if (pdfs.isEmpty) {
      _message(context, 'There are no PDFs to export.');
      return;
    }

    var exported = 0;
    for (final item in pdfs) {
      try {
        final result = await PrivateToPublicPdfManager().exportSingleFile(
          sandboxPath: item.path,
          suggestedName: item.fileName,
        );
        if (result != null) exported++;
      } catch (_) {
        // Reported through the summary message below.
      }
    }

    if (!context.mounted) return;
    _message(
      context,
      exported == 0
          ? 'Export cancelled.'
          : 'Exported $exported PDF file(s).',
    );
  }

  /// Saves any mix of images and PDFs with the right mechanism for each.
  static Future<void> save(
    BuildContext context,
    List<AppFileItem> items,
  ) async {
    final images = items.where((item) => item.isImage).toList();
    final pdfs = items.where((item) => item.isPdf).toList();
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
  }) async {
    final controller = TextEditingController(text: initialValue);
    final formKey = GlobalKey<FormState>();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: label,
              border: const OutlineInputBorder(),
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Please enter a name';
              }
              return null;
            },
            onFieldSubmitted: (_) {
              if (formKey.currentState?.validate() == true) {
                Navigator.of(dialogContext).pop(controller.text.trim());
              }
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() == true) {
                Navigator.of(dialogContext).pop(controller.text.trim());
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  static void _message(BuildContext context, String text) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
    );
  }
}
