// ignore_for_file: avoid_print
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pixeltools/features/camera/models/scanned_page.dart';
import 'package:pixeltools/features/camera/services/document_enhancement_service.dart';
import 'package:pixeltools/features/camera/services/image_filter_service.dart';
import 'package:pixeltools/features/camera/services/magic_remove_service.dart';
import 'package:pixeltools/features/camera/services/perspective_correction_service.dart';

Uint8List solid(int w, int h, int r, int g, int b) {
  final image = img.Image(width: w, height: h);
  img.fill(image, color: img.ColorRgb8(r, g, b));
  return Uint8List.fromList(img.encodeJpg(image, quality: 100));
}

Uint8List whiteWithRedCenter() {
  final image = img.Image(width: 100, height: 100);
  img.fill(image, color: img.ColorRgb8(255, 255, 255));
  for (var y = 30; y < 70; y++) {
    for (var x = 30; x < 70; x++) {
      image.setPixelRgba(x, y, 220, 30, 30, 255);
    }
  }
  return Uint8List.fromList(img.encodeJpg(image, quality: 100));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('garbage bytes', () async {
    final garbage = Uint8List.fromList(List.generate(200, (i) => i % 251));
    try {
      final r = await ImageFilterService.applyFilter(garbage, FilterType.lighten);
      print('garbage filter => $r');
    } catch (e) {
      print('garbage filter threw: $e');
    }
    final decoded = img.decodeImage(garbage);
    print('garbage decode => $decoded');
  });

  test('rotate direction', () async {
    final image = img.Image(width: 40, height: 20);
    for (var y = 0; y < 20; y++) {
      for (var x = 0; x < 40; x++) {
        final c = (x < 20 && y < 10) ? 255 : 0;
        image.setPixelRgba(x, y, c, 0, 0, 255);
      }
    }
    final bytes = Uint8List.fromList(img.encodeJpg(image, quality: 100));
    final r90 = await ImageFilterService.rotate90(bytes);
    final d90 = img.decodeImage(r90!.bytes)!;
    print('rot90 dims ${d90.width}x${d90.height}');
    print('rot90 (0,0)=${d90.getPixel(0, 0)} (max,0)=${d90.getPixel(d90.width - 1, 0)}'
        ' (0,max)=${d90.getPixel(0, d90.height - 1)}');
    final r270 = await ImageFilterService.rotate270(bytes);
    final d270 = img.decodeImage(r270!.bytes)!;
    print('rot270 dims ${d270.width}x${d270.height}');
    print('rot270 (0,0)=${d270.getPixel(0, 0)} (max,0)=${d270.getPixel(d270.width - 1, 0)}');
    final round = await ImageFilterService.rotate90(r90.bytes);
    final dround = img.decodeImage(round!.bytes)!;
    print('roundtrip dims ${dround.width}x${dround.height}');
    print('round (0,0)=${dround.getPixel(0, 0)} (max,0)=${dround.getPixel(dround.width - 1, 0)}');
  });

  test('perspective identity & degenerate', () async {
    final bytes = whiteWithRedCenter();
    final id = await PerspectiveCorrectionService.correct(
      bytes: bytes,
      srcPoints: const [
        Offset(0, 0),
        Offset(100, 0),
        Offset(100, 100),
        Offset(0, 100),
      ],
      targetWidth: 100,
      targetHeight: 100,
    );
    print('identity => ${id?.width}x${id?.height}');
    if (id != null) {
      final before = img.decodeImage(bytes)!;
      final after = img.decodeImage(id.bytes)!;
      var diff = 0, n = 0;
      for (var y = 0; y < 100; y++) {
        for (var x = 0; x < 100; x++) {
          diff += (before.getPixel(x, y).r - after.getPixel(x, y).r).abs().round();
          n++;
        }
      }
      print('identity mean r diff = ${diff / n}');
    }

    // degenerate: all four points identical
    try {
      final deg = await PerspectiveCorrectionService.correct(
        bytes: bytes,
        srcPoints: const [
          Offset(50, 50),
          Offset(50, 50),
          Offset(50, 50),
          Offset(50, 50),
        ],
        targetWidth: 60,
        targetHeight: 60,
      );
      if (deg == null) {
        print('degenerate => null');
      } else {
        final d = img.decodeImage(deg.bytes)!;
        var maxV = 0;
        for (final p in d) {
          if (p.r > maxV) maxV = p.r.toInt();
        }
        print('degenerate => ${deg.width}x${deg.height} maxR=$maxV');
      }
    } catch (e) {
      print('degenerate threw: $e');
    }

    // collinear points
    try {
      final col = await PerspectiveCorrectionService.correct(
        bytes: bytes,
        srcPoints: const [
          Offset(0, 0),
          Offset(30, 0),
          Offset(60, 0),
          Offset(90, 0),
        ],
        targetWidth: 60,
        targetHeight: 60,
      );
      if (col == null) {
        print('collinear => null');
      } else {
        final d = img.decodeImage(col.bytes)!;
        var maxV = 0;
        for (final p in d) {
          if (p.r > maxV) maxV = p.r.toInt();
        }
        print('collinear => ${col.width}x${col.height} maxR=$maxV');
      }
    } catch (e) {
      print('collinear threw: $e');
    }

    // fewer than 4 points
    try {
      final few = await PerspectiveCorrectionService.correct(
        bytes: bytes,
        srcPoints: const [Offset(0, 0), Offset(10, 0), Offset(10, 10)],
        targetWidth: 60,
        targetHeight: 60,
      );
      print('few points => ${few?.width}');
    } catch (e) {
      print('few points threw: ${e.runtimeType}');
    }
  });

  test('perspective crop quad', () async {
    final bytes = whiteWithRedCenter();
    final res = await PerspectiveCorrectionService.correct(
      bytes: bytes,
      srcPoints: const [
        Offset(25, 25),
        Offset(75, 25),
        Offset(75, 75),
        Offset(25, 75),
      ],
      targetWidth: 50,
      targetHeight: 50,
    );
    final d = img.decodeImage(res!.bytes)!;
    print('crop center=${d.getPixel(25, 25)} corner=${d.getPixel(0, 0)}');
  });

  test('magic remove basic', () async {
    final image = img.Image(width: 120, height: 120);
    img.fill(image, color: img.ColorRgb8(240, 240, 240));
    for (var y = 50; y < 70; y++) {
      for (var x = 50; x < 70; x++) {
        image.setPixelRgba(x, y, 10, 10, 10, 255);
      }
    }
    final bytes = Uint8List.fromList(img.encodeJpg(image, quality: 95));
    final out = await MagicRemoveService.inpaintObject(
      imageBytes: bytes,
      points: const [Offset(60, 60)],
      brushRadius: 12,
      imageWidth: 120,
      imageHeight: 120,
    );
    final d = img.decodeImage(out!)!;
    print('dims ${d.width}x${d.height}');
    print('center before=${img.decodeImage(bytes)!.getPixel(60, 60)}');
    print('center after=${d.getPixel(60, 60)}');
    print('far after=${d.getPixel(5, 5)} before=${img.decodeImage(bytes)!.getPixel(5, 5)}');

    // empty points
    final same = await MagicRemoveService.inpaintObject(
      imageBytes: bytes,
      points: const [],
      brushRadius: 12,
      imageWidth: 120,
      imageHeight: 120,
    );
    print('empty points identical: ${identical(same, bytes)} ${same?.length == bytes.length}');
    // zero dims
    final zero = await MagicRemoveService.inpaintObject(
      imageBytes: bytes,
      points: const [Offset(60, 60)],
      brushRadius: 12,
      imageWidth: 0,
      imageHeight: 120,
    );
    print('zero width identical: ${identical(zero, bytes)}');
    // outside points
    final outside = await MagicRemoveService.inpaintObject(
      imageBytes: bytes,
      points: const [Offset(-500, -500)],
      brushRadius: 10,
      imageWidth: 120,
      imageHeight: 120,
    );
    print('outside identical bytes: ${_sameBytes(outside!, bytes)}');
  });

  test('magic remove edge points', () async {
    final image = img.Image(width: 120, height: 120);
    img.fill(image, color: img.ColorRgb8(240, 240, 240));
    for (var y = 0; y < 20; y++) {
      for (var x = 0; x < 20; x++) {
        image.setPixelRgba(x, y, 10, 10, 10, 255);
      }
    }
    final bytes = Uint8List.fromList(img.encodeJpg(image, quality: 95));
    final out = await MagicRemoveService.inpaintObject(
      imageBytes: bytes,
      points: const [Offset(5, 5), Offset(10, 12)],
      brushRadius: 8,
      imageWidth: 120,
      imageHeight: 120,
    );
    final d = img.decodeImage(out!)!;
    print('edge dims ${d.width}x${d.height} corner=${d.getPixel(6, 6)}');
  });

  test('intrusions', () async {
    final image = img.Image(width: 480, height: 360);
    img.fill(image, color: img.ColorRgb8(245, 245, 245));
    for (var y = 120; y < 280; y++) {
      for (var x = 0; x < 90; x++) {
        image.setPixelRgba(x, y, 20, 20, 20, 255);
      }
    }
    final bytes = Uint8List.fromList(img.encodeJpg(image, quality: 95));
    final clusters = await MagicRemoveService.detectIntrusions(
      imageBytes: bytes,
      canvasWidth: 300,
      canvasHeight: 200,
    );
    print('clusters=${clusters.length}');
    for (final c in clusters) {
      print('  cluster pts=${c.length} first=${c.first} last=${c.last}');
    }
    final plain = img.Image(width: 480, height: 360);
    img.fill(plain, color: img.ColorRgb8(245, 245, 245));
    final empty = await MagicRemoveService.detectIntrusions(
      imageBytes: Uint8List.fromList(img.encodeJpg(plain, quality: 95)),
      canvasWidth: 300,
      canvasHeight: 200,
    );
    print('plain image clusters=${empty.length}');
    final bad = await MagicRemoveService.detectIntrusions(
      imageBytes: bytes,
      canvasWidth: 0,
      canvasHeight: 10,
    );
    print('bad canvas=${bad.length}');
  });

  test('enhancement wrappers', () async {
    // bordered "desk" image: dark border, white paper inside
    final image = img.Image(width: 360, height: 360);
    img.fill(image, color: img.ColorRgb8(60, 60, 60));
    for (var y = 70; y < 290; y++) {
      for (var x = 70; x < 290; x++) {
        image.setPixelRgba(x, y, 245, 245, 245, 255);
      }
    }
    final bytes = Uint8List.fromList(img.encodeJpg(image, quality: 95));
    final fitted = await DocumentEnhancementService.autoFitToPaper(bytes);
    if (fitted != null) {
      final d = img.decodeImage(fitted)!;
      print('autoFit dims ${d.width}x${d.height}');
    }

    final dark = img.Image(width: 80, height: 80);
    for (var y = 0; y < 80; y++) {
      for (var x = 0; x < 80; x++) {
        dark.setPixelRgba(x, y, 50, 50, 50, 255);
      }
    }
    final darkBytes = Uint8List.fromList(img.encodeJpg(dark, quality: 95));
    final bright = await DocumentEnhancementService.autoAdjustDarkImage(darkBytes);
    final bd = img.decodeImage(bright!)!;
    print('bright center=${bd.getPixel(40, 40)}');

    final even = img.Image(width: 120, height: 120);
    for (var y = 0; y < 120; y++) {
      for (var x = 0; x < 120; x++) {
        even.setPixelRgba(x, y, 240, 240, 240, 255);
      }
    }
    print('even illumination=${DocumentEnhancementService.internalHasUnevenIllumination(even)}');
    final grad = img.Image(width: 120, height: 120);
    for (var y = 0; y < 120; y++) {
      for (var x = 0; x < 120; x++) {
        final v = (60 + (x / 120) * 180).toInt();
        grad.setPixelRgba(x, y, v, v, v, 255);
      }
    }
    print('grad illumination=${DocumentEnhancementService.internalHasUnevenIllumination(grad)}');

    final anti = await DocumentEnhancementService.autocorrectAntiLightShadows(
        Uint8List.fromList(img.encodeJpg(grad, quality: 95)));
    final ad = img.decodeImage(anti!)!;
    print('anti dims ${ad.width}x${ad.height}');
    var lo = 255, hi = 0;
    for (var x = 0; x < 120; x += 20) {
      final v = ad.getPixel(x, 60).r.toInt();
      if (v < lo) lo = v;
      if (v > hi) hi = v;
    }
    print('anti row range lo=$lo hi=$hi');
    var lo0 = 255, hi0 = 0;
    for (var x = 0; x < 120; x += 20) {
      final v = grad.getPixel(x, 60).r.toInt();
      if (v < lo0) lo0 = v;
      if (v > hi0) hi0 = v;
    }
    print('src row range lo=$lo0 hi=$hi0');

    final corners = await DocumentEnhancementService.detectDocumentCorners(bytes);
    print('corners=$corners');

    final detailed = await DocumentEnhancementService.smartScanEnhanceDetailed(bytes);
    print('stages=${detailed?.stages}');

    final flatten = await DocumentEnhancementService.flattenDocument(bytes);
    print('flatten=${flatten?.length}');
  });

  test('preview downscale', () async {
    final big = solid(1600, 1200, 200, 200, 200);
    final r = await ImageFilterService.applyPreview(big, FilterType.lighten);
    final d = img.decodeImage(r!.bytes)!;
    print('preview dims ${d.width}x${d.height} declared ${r.width}x${r.height}');

    final none = await ImageFilterService.applyFilter(big, FilterType.none);
    print('none filter=$none');
    final noneP = await ImageFilterService.applyPreview(big, FilterType.none);
    print('none preview=$noneP');
  });

  test('binarization stats', () async {
    final image = img.Image(width: 120, height: 120);
    img.fill(image, color: img.ColorRgb8(240, 240, 240));
    for (var y = 40; y < 80; y++) {
      for (var x = 20; x < 100; x++) {
        image.setPixelRgba(x, y, 30, 30, 30, 255);
      }
    }
    final bytes = Uint8List.fromList(img.encodeJpg(image, quality: 95));
    final r = await ImageFilterService.applyBinarization(bytes);
    final d = img.decodeImage(r!.bytes)!;
    var extreme = 0, total = 0, sum = 0;
    for (final p in d) {
      total++;
      final v = p.r.toInt();
      if (v < 30 || v > 225) extreme++;
      sum += v;
    }
    print('binarize extreme=${extreme / total} mean=${sum / total}');

    final inv = await ImageFilterService.applyFilter(bytes, FilterType.invert);
    final di = img.decodeImage(inv!.bytes)!;
    print('invert center=${di.getPixel(60, 60)} src=${image.getPixel(60, 60)}');

    final gray = await ImageFilterService.applyFilter(bytes, FilterType.grayscale);
    final dg = img.decodeImage(gray!.bytes)!;
    final p = dg.getPixel(10, 10);
    print('grayscale sample=$p');
    var maxDiff = 0;
    for (final q in dg) {
      final d1 = (q.r - q.g).abs().round();
      final d2 = (q.g - q.b).abs().round();
      if (d1 > maxDiff) maxDiff = d1;
      if (d2 > maxDiff) maxDiff = d2;
    }
    print('grayscale max channel diff=$maxDiff');
  });
}

bool _sameBytes(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
