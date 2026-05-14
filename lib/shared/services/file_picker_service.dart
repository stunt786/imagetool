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
    final type = FileType.custom;
    final allowedExtensions = switch (target) {
      PickTarget.images => _imageExtensions,
      PickTarget.pdfs => const <String>['pdf'],
    };

    final result = await FilePicker.platform.pickFiles(
      allowMultiple: allowMultiple,
      type: type,
      allowedExtensions: allowedExtensions,
      withData: false,
      withReadStream: true,
    );

    final files = result?.files ?? const <PlatformFile>[];
    return files
        .map(
          (f) => PickedFile(
            name: f.name,
            sizeBytes: f.size,
            extension: f.extension,
            path: f.path,
          ),
        )
        .toList(growable: false);
  }
}

