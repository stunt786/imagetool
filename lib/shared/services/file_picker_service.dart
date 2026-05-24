import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';

import '../models/picked_file.dart';

enum PickTarget { images, pdfs }

final filePickerServiceProvider = Provider<FilePickerService>((ref) {
  return FilePickerService();
});

class FilePickerService {
  Future<List<PickedFile>> pick({
    required BuildContext context,
    required PickTarget target,
    required bool allowMultiple,
  }) async {
    if (target == PickTarget.images) {
      return _pickAssets(context, allowMultiple);
    }

    final result = await FilePicker.pickFiles(
      allowMultiple: allowMultiple,
      type: FileType.custom,
      allowedExtensions: const <String>['pdf'],
      withData: true,
      withReadStream: false,
    );

    final files = result?.files ?? const <PlatformFile>[];
    final pickedFiles = files
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

    FilePicker.clearTemporaryFiles().ignore();
    return pickedFiles;
  }

  Future<List<PickedFile>> _pickAssets(
    BuildContext context,
    bool allowMultiple,
  ) async {
    final PermissionState ps = await PhotoManager.requestPermissionExtend();
    if (!ps.isAuth && !ps.hasAccess) {
      return [];
    }

    final List<AssetEntity>? result = await AssetPicker.pickAssets(
      context,
      pickerConfig: AssetPickerConfig(
        maxAssets: allowMultiple ? 100 : 1,
        requestType: RequestType.image,
      ),
    );

    if (result == null || result.isEmpty) return [];

    final pickedFiles = <PickedFile>[];
    for (final entity in result) {
      final bytes = await entity.originBytes;
      if (bytes == null) continue;

      final ext = (entity.title?.split('.').last.toLowerCase()) ?? 'jpg';
      pickedFiles.add(
        PickedFile(
          name: entity.title ?? 'image_${DateTime.now().millisecondsSinceEpoch}',
          sizeBytes: bytes.length,
          extension: ext,
          path: null,
          bytes: bytes,
        ),
      );
    }

    return pickedFiles;
  }
}
