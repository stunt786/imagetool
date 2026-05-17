import 'dart:typed_data';

import 'image_saver_stub.dart'
    if (dart.library.io) 'image_saver_io.dart'
    if (dart.library.html) 'image_saver_web.dart';
import 'image_saver_types.dart';

export 'image_saver_types.dart';

Future<ImageSaveResult> saveImageBytes(Uint8List bytes, {required String fileName}) {
  return saveImageBytesImpl(bytes, fileName: fileName);
}

Future<List<ImageSaveResult>> saveMultipleImages(
  List<({Uint8List bytes, String fileName})> items,
) {
  return saveMultipleImagesImpl(items);
}
