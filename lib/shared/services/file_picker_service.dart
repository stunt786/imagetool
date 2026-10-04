import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';
import 'dart:typed_data';

import '../models/picked_file.dart';
import '../../core/utils/file_type_detector.dart';

enum PickTarget { images, pdfs }

final filePickerServiceProvider = Provider<FilePickerService>((ref) {
  return FilePickerService();
});

class FilePickerService {
  /// Upper bound when a caller does not pass an explicit [maxAssets].
  ///
  /// Deliberately modest: every picked image used to be buffered at full
  /// resolution, so a permissive default translated straight into peak RSS.
  static const int _defaultMaxAssets = 20;

  Future<List<PickedFile>> pick({
    required BuildContext context,
    required PickTarget target,
    required bool allowMultiple,
    int? maxAssets,
  }) async {
    if (target == PickTarget.images) {
      return _pickAssets(context, allowMultiple, maxAssets: maxAssets);
    }

    final result = await FilePicker.pickFiles(
      allowMultiple: allowMultiple,
      type: FileType.custom,
      allowedExtensions: const <String>['pdf'],
      // Never load full file bytes here: a large PDF would sit in RAM 3-4x
      // over (picker bytes + sandbox copy + processing copies) and OOM.
      // Prefer the file path; only buffer bytes when no path is available.
      withData: false,
      withReadStream: true,
    );

    final files = result?.files ?? const <PlatformFile>[];
    final pickedFiles = <PickedFile>[];
    for (final f in files) {
      Uint8List? bytes;
      if (f.path == null || f.path!.isEmpty) {
        bytes = await _readStreamBytes(f);
      }
      pickedFiles.add(
        PickedFile(
          name: f.name,
          sizeBytes: f.size,
          extension: f.extension,
          path: f.path,
          bytes: bytes,
        ),
      );
    }
    // NOTE: do not call FilePicker.clearTemporaryFiles() here. On Android the
    // returned path can point into the picker cache, so clearing deletes the
    // very file the caller is about to copy (PathNotFound on import).
    return pickedFiles;
  }

  /// Buffers a platform read-stream into bytes (fallback for pickers that
  /// provide no usable file path, e.g. web / cloud providers).
  static Future<Uint8List?> _readStreamBytes(PlatformFile f) async {
    final stream = f.readStream;
    if (stream == null) return null;
    final chunks = <List<int>>[];
    var total = 0;
    await for (final chunk in stream) {
      chunks.add(chunk);
      total += chunk.length;
    }
    if (total == 0) return null;
    final bytes = Uint8List(total);
    var offset = 0;
    for (final chunk in chunks) {
      bytes.setRange(offset, offset + chunk.length, chunk);
      offset += chunk.length;
    }
    return bytes;
  }

  Future<List<PickedFile>> _pickAssets(
    BuildContext context,
    bool allowMultiple, {
    int? maxAssets,
  }) async {
    final PermissionState ps = await PhotoManager.requestPermissionExtend(
      requestOption: const PermissionRequestOption(
        androidPermission: AndroidPermission(
          type: RequestType.image,
          mediaLocation: false,
        ),
      ),
    );
    if (!ps.isAuth && !ps.hasAccess) {
      return [];
    }
    if (!context.mounted) return [];

    final limit = maxAssets != null && maxAssets > 0
        ? maxAssets
        : (allowMultiple ? _defaultMaxAssets : 1);
    final List<AssetEntity>? result = await AssetPicker.pickAssets(
      context,
      pickerConfig: AssetPickerConfig(
        maxAssets: allowMultiple ? limit : 1,
        requestType: RequestType.image,
      ),
    );

    if (result == null || result.isEmpty) return [];

    final pickedFiles = <PickedFile>[];
    for (final entity in result) {
      // Keep the native path when one is available. This lets an editor honour
      // an explicit replacement request instead of always creating an export.
      final originFile = await entity.originFile;
      final originPath = originFile?.path;
      final title = entity.title;
      final name = title ?? 'image_${DateTime.now().millisecondsSinceEpoch}';

      final dot = title == null ? -1 : title.lastIndexOf('.');
      final rawExt = (dot >= 0 && dot < title!.length - 1)
          ? title.substring(dot + 1).toLowerCase()
          : '';
      final ext = rawExt.isNotEmpty ? rawExt : 'jpg';

      // Defer the payload whenever a readable path exists: consumers read it
      // back through PickedFile.resolveBytes(). Buffering every selected
      // asset at full resolution here made the picker the largest single
      // source of retained image memory.
      //
      // When the name does not already identify a supported image we still
      // need the header bytes, because FileTypeDetector falls back to the
      // extension once bytes are absent.
      final pathIsReadable = originPath != null && originPath.isNotEmpty;
      final canDefer =
          pathIsReadable && FileTypeDetector.imageExtensions.contains(rawExt);

      Uint8List? bytes;
      var sizeBytes = 0;
      if (canDefer) {
        try {
          sizeBytes = await originFile!.length();
        } catch (_) {
          bytes = await entity.originBytes;
        }
      } else {
        bytes = await entity.originBytes;
      }

      if (bytes != null) sizeBytes = bytes.length;
      if (bytes == null && !canDefer) continue;

      pickedFiles.add(
        PickedFile(
          name: name,
          sizeBytes: sizeBytes,
          extension: ext,
          path: pathIsReadable ? originPath : null,
          bytes: bytes,
        ),
      );
    }

    return pickedFiles;
  }
}
