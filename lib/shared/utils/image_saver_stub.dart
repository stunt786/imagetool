import 'dart:typed_data';

import 'image_saver_types.dart';

abstract final class AppSavePaths {
  static const String defaultDirectoryName = 'PixelTools';
}

Future<ImageSaveResult> saveImageBytesImpl(Uint8List bytes, {required String fileName}) async {
  throw UnsupportedError('Saving images is not supported on this platform.');
}

Future<List<ImageSaveResult>> saveMultipleImagesImpl(
  List<({Uint8List bytes, String fileName})> items,
) async {
  throw UnsupportedError('Saving images is not supported on this platform.');
}
