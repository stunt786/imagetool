import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/picked_file.dart';

enum PickTarget { images, pdfs }

final filePickerServiceProvider = Provider<FilePickerService>((ref) {
  return const FilePickerService();
});

class FilePickerService {
  const FilePickerService();

  static const List<String> _imageExtensions = <String>[
    'jpg',
    'jpeg',
    'png',
    'webp',
    'avif',
    'gif',
    'bmp',
    'tif',
    'tiff',
    'heic',
    'heif',
  ];

  Future<List<PickedFile>> pick({
    required PickTarget target,
    required bool allowMultiple,
  }) async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: allowMultiple,
      type: target == PickTarget.images ? FileType.image : FileType.custom,
      allowedExtensions:
          target == PickTarget.images ? null : const <String>['pdf'],
      withData: true,
      withReadStream: false,
    );

    // Extract all data into our own model objects first (bytes are now in
    // memory via withData:true), then immediately clear the temporary copies
    // that file_picker creates on Android. Those copies can be picked up by
    // Android's MediaStore and incorrectly show up in the device's Pictures
    // directory alongside our real output files.
    final files = result?.files ?? const <PlatformFile>[];
    final filteredFiles = target == PickTarget.images
        ? files.where((f) {
            final ext = f.extension?.toLowerCase();
            return ext != null && _imageExtensions.contains(ext);
          }).toList()
        : files;

    final pickedFiles = filteredFiles
        .map(
          (f) => PickedFile(
            name: f.name,
            sizeBytes: f.size,
            extension: f.extension,
            path: f.path,
            bytes: f.bytes,
          ),
        )
        .toList(growable: false);

    // Schedule temp-file cleanup as a fire-and-forget AFTER returning the
    // result. Awaiting it synchronously can interfere with native buffers
    // still referenced by the platform channel (Android) or cause unexpected
    // behaviour on web. `.ignore()` explicitly suppresses unhandled-future
    // warnings while letting the cleanup run in the background.
    FilePicker.platform.clearTemporaryFiles().ignore();

    return pickedFiles;
  }
}

