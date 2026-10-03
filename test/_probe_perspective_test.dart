import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pixeltools/features/camera/services/perspective_correction_service.dart';

Uint8List _gradient(int w, int h) {
  final image = img.Image(width: w, height: h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final v = (x * 200 / w + y * 55 / h).round().clamp(0, 255);
      image.setPixelRgba(x, y, v, v, v, 255);
    }
  }
  return Uint8List.fromList(img.encodePng(image));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('explore degenerate quads', () async {
    final bytes = _gradient(80, 80);
    final cases = <String, List<Offset>>{
      'identical points': const [
        Offset(40, 40),
        Offset(40, 40),
        Offset(40, 40),
        Offset(40, 40)
      ],
      'collinear': const [
        Offset(10, 40),
        Offset(30, 40),
        Offset(50, 40),
        Offset(70, 40)
      ],
      'two duplicated': const [
        Offset(10, 10),
        Offset(70, 10),
        Offset(70, 10),
        Offset(10, 70)
      ],
      'triangle': const [
        Offset(10, 10),
        Offset(70, 10),
        Offset(40, 70),
        Offset(40, 70)
      ],
    };
    for (final entry in cases.entries) {
      final result = await PerspectiveCorrectionService.correct(
        bytes: bytes,
        srcPoints: entry.value,
        targetWidth: 40,
        targetHeight: 40,
      );
      if (result == null) {
        print('${entry.key}: null');
        continue;
      }
      final decoded = img.decodeImage(result.bytes);
      var sum = 0;
      var count = 0;
      if (decoded != null) {
        for (final p in decoded) {
          sum += p.r.toInt();
          count++;
        }
      }
      print('${entry.key}: ${result.width}x${result.height} decoded='
          '${decoded?.width}x${decoded?.height} mean=${sum / count}');
    }
  });
}
