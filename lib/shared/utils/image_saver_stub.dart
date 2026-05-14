import 'dart:typed_data';

import 'image_saver_types.dart';

Future<ImageSaveResult> saveImageBytesImpl(Uint8List bytes, {required String fileName}) async {
  throw UnsupportedError('Saving images is not supported on this platform.');
}
