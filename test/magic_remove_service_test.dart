import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pixeltools/features/camera/services/magic_remove_service.dart';

Uint8List _paperWithBlob() {
  const size = 120;
  final image = img.Image(width: size, height: size);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      image.setPixelRgba(x, y, 240, 240, 240, 255);
    }
  }
  // Dark "object" sitting in the middle of the page.
  for (var y = 54; y <= 66; y++) {
    for (var x = 54; x <= 66; x++) {
      image.setPixelRgba(x, y, 25, 25, 25, 255);
    }
  }
  return Uint8List.fromList(img.encodePng(image));
}

Uint8List _cleanPaper({int size = 120, int value = 230}) {
  final image = img.Image(width: size, height: size);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      image.setPixelRgba(x, y, value, value, value, 255);
    }
  }
  return Uint8List.fromList(img.encodePng(image));
}

/// White page with a dark intrusion bleeding in from the left border.
Uint8List _paperWithBorderIntrusion() {
  const size = 120;
  final image = img.Image(width: size, height: size);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      image.setPixelRgba(x, y, 230, 230, 230, 255);
    }
  }
  for (var y = 40; y <= 80; y++) {
    for (var x = 0; x <= 12; x++) {
      image.setPixelRgba(x, y, 35, 35, 35, 255);
    }
  }
  return Uint8List.fromList(img.encodePng(image));
}

int _channelAt(img.Image image, int x, int y) => image.getPixel(x, y).r.toInt();

double _meanChannel(img.Image image, int x0, int y0, int x1, int y1) {
  var sum = 0.0;
  var count = 0;
  for (var y = y0; y <= y1; y++) {
    for (var x = x0; x <= x1; x++) {
      sum += image.getPixel(x, y).r.toDouble();
      count++;
    }
  }
  return sum / count;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MagicRemoveService.inpaintObject', () {
    test('empty brush strokes hand the input straight back', () async {
      final bytes = _paperWithBlob();
      final result = await MagicRemoveService.inpaintObject(
        imageBytes: bytes,
        points: const [],
        brushRadius: 8,
        imageWidth: 120,
        imageHeight: 120,
      );
      expect(result, same(bytes));
    });

    test('a non-positive canvas size is rejected without touching the image',
        () async {
      final bytes = _paperWithBlob();
      final result = await MagicRemoveService.inpaintObject(
        imageBytes: bytes,
        points: const [Offset(10, 10)],
        brushRadius: 8,
        imageWidth: 0,
        imageHeight: 120,
      );
      expect(result, same(bytes));
    });

    test('undecodable image bytes produce null instead of throwing', () async {
      final result = await MagicRemoveService.inpaintObject(
        imageBytes: Uint8List.fromList(List<int>.generate(64, (i) => i)),
        points: const [Offset(10, 10), Offset(20, 20)],
        brushRadius: 6,
        imageWidth: 120,
        imageHeight: 120,
      );
      expect(result, isNull);
    });

    test('masks the stroked region while keeping the output dimensions',
        () async {
      final bytes = _paperWithBlob();
      final source = img.decodeImage(bytes)!;
      expect(_channelAt(source, 60, 60), lessThan(50));

      final result = await MagicRemoveService.inpaintObject(
        imageBytes: bytes,
        // The stroke starts and ends on the paper so the mask boundary
        // samples the background around the object.
        points: const [Offset(40, 60), Offset(80, 60)],
        brushRadius: 6,
        imageWidth: 120,
        imageHeight: 120,
      );

      expect(result, isNotNull);
      final out = img.decodeImage(result!)!;
      expect(out.width, 120);
      expect(out.height, 120);

      // The masked blob is replaced by the surrounding paper colour.
      expect(_channelAt(out, 60, 60), greaterThan(150),
          reason: 'masked pixels must be inpainted');
      expect(_meanChannel(out, 50, 50, 70, 70), greaterThan(140),
          reason: 'the whole masked region must move away from black');

      // Areas far away from the mask stay visually intact.
      expect(_channelAt(out, 5, 5), closeTo(240, 15));
      expect(_channelAt(out, 114, 114), closeTo(240, 15));

      // Something actually changed in the masked area.
      var changed = 0;
      for (var y = 50; y <= 70; y++) {
        for (var x = 50; x <= 70; x++) {
          if ((_channelAt(source, x, y) - _channelAt(out, x, y)).abs() > 30) {
            changed++;
          }
        }
      }
      expect(changed, greaterThan(100));
    });

    test('strokes near the image corner are clamped to the raster', () async {
      final bytes = _cleanPaper();
      final result = await MagicRemoveService.inpaintObject(
        imageBytes: bytes,
        points: const [Offset(0, 0), Offset(3, 4), Offset(8, 2)],
        brushRadius: 10,
        imageWidth: 120,
        imageHeight: 120,
      );

      expect(result, isNotNull);
      final out = img.decodeImage(result!)!;
      expect(out.width, 120);
      expect(out.height, 120);
    });

    test('a mask that lands outside the raster leaves the pixels untouched',
        () async {
      final bytes = _cleanPaper();
      final result = await MagicRemoveService.inpaintObject(
        imageBytes: bytes,
        points: const [Offset(4000, 4000), Offset(4100, 4100)],
        brushRadius: 8,
        imageWidth: 120,
        imageHeight: 120,
      );

      expect(result, isNotNull);
      expect(result, isNotEmpty);
      final source = img.decodeImage(bytes)!;
      final out = img.decodeImage(result!)!;
      expect(out.width, source.width);
      expect(out.height, source.height);
      expect(_channelAt(out, 60, 60), _channelAt(source, 60, 60));
      expect(_channelAt(out, 10, 10), _channelAt(source, 10, 10));
    });
  });

  group('MagicRemoveService.detectIntrusions', () {
    test('non-positive canvas sizes return no clusters', () async {
      expect(
        await MagicRemoveService.detectIntrusions(
          imageBytes: _cleanPaper(),
          canvasWidth: 0,
          canvasHeight: 100,
        ),
        isEmpty,
      );
      expect(
        await MagicRemoveService.detectIntrusions(
          imageBytes: _cleanPaper(),
          canvasWidth: 100,
          canvasHeight: -5,
        ),
        isEmpty,
      );
    });

    test('a clean page has no border intrusions', () async {
      final clusters = await MagicRemoveService.detectIntrusions(
        imageBytes: _cleanPaper(),
        canvasWidth: 300,
        canvasHeight: 400,
      );
      expect(clusters, isEmpty);
    });

    test('undecodable bytes return no clusters instead of throwing', () async {
      final clusters = await MagicRemoveService.detectIntrusions(
        imageBytes: Uint8List.fromList(List<int>.filled(48, 7)),
        canvasWidth: 300,
        canvasHeight: 400,
      );
      expect(clusters, isEmpty);
    });

    test('a dark intrusion touching the border is reported inside the canvas',
        () async {
      const canvasW = 300.0;
      const canvasH = 400.0;
      final clusters = await MagicRemoveService.detectIntrusions(
        imageBytes: _paperWithBorderIntrusion(),
        canvasWidth: canvasW,
        canvasHeight: canvasH,
      );

      expect(clusters, isNotEmpty);
      expect(clusters.length, lessThanOrEqualTo(6));
      final cluster = clusters.first;
      expect(cluster.length, greaterThan(1));

      for (final point in cluster) {
        expect(point.dx, inInclusiveRange(0.0, canvasW));
        expect(point.dy, inInclusiveRange(0.0, canvasH));
      }

      // The scribble spans the intrusion, which hugs the left border.
      final xs = cluster.map((p) => p.dx).toList();
      expect(xs.first, lessThan(canvasW * 0.25));
      expect(xs.last, lessThan(canvasW * 0.35));
      expect(
        cluster.map((p) => p.dy).reduce((a, b) => a > b ? a : b),
        greaterThan(canvasH * 0.2),
        reason: 'the scribble must run across the middle of the blob',
      );
    });
  });
}
