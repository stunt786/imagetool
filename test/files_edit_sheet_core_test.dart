import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:pixeltools/core/models/operation_folder.dart';
import 'package:pixeltools/core/services/image_isolate_service.dart';
import 'package:pixeltools/core/services/operation_store.dart';
import 'package:pixeltools/core/services/output_saver.dart';
import 'package:pixeltools/core/services/platform_image_encoder.dart';
import 'package:pixeltools/core/services/public_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory base;
  late OperationStore store;
  late String imagePath;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    base = await Directory.systemTemp.createTemp('edit_sheet_core_');
    store = OperationStore(baseDirectoryProvider: () async => base);
    final sourceDir = await Directory.systemTemp.createTemp('edit_sheet_src_');
    final image = img.Image(width: 80, height: 60);
    img.fill(image, color: img.ColorRgb8(20, 120, 220));
    imagePath = '${sourceDir.path}/photo.jpg';
    await File(imagePath).writeAsBytes(img.encodeJpg(image));
  });

  tearDown(() async {
    try {
      await base.delete(recursive: true);
    } catch (_) {}
  });

  Future<List<File>> outputs() async {
    final out = <File>[];
    await for (final entity in base.list(recursive: true)) {
      if (entity is File) out.add(entity);
    }
    return out;
  }

  test('resize pipeline writes an output file', () async {
    final bytes = await File(imagePath).readAsBytes();
    final probe = await ImageIsolateService.probe(bytes);
    expect(probe.isValid, isTrue);

    final resized = await ImageIsolateService.transform(
      bytes,
      ImageTransformRequest(
        targetExtension: 'jpg',
        quality: 85,
        maxWidth: (probe.width * 0.5).round(),
        maxHeight: (probe.height * 0.5).round(),
      ),
    );
    expect(resized, isNotNull);

    final saved = await saveToolOutputs(
      store,
      kind: OperationKind.resize,
      entries: [
        OutputEntry.bytes(
          bytes: resized!,
          fileName: 'pixeltools_photo_resized_1.jpg',
          publicKind: PublicFileKind.image,
        ),
      ],
    );
    expect(saved, hasLength(1));
    expect(await File(saved.first.localPath).exists(), isTrue);

    final files = await outputs();
    // ignore: avoid_print
    print('RESIZE OUTPUT: ${files.map((f) => f.path).toList()}');
    expect(files, isNotEmpty);
  });

  test('convert to tiff pipeline writes a .tiff file', () async {
    final bytes = await File(imagePath).readAsBytes();
    final converted = await ImageIsolateService.transform(
      bytes,
      ImageTransformRequest(targetExtension: 'tiff', quality: 90),
    );
    expect(converted, isNotNull);
    expect(converted!.length, greaterThan(8));

    final saved = await saveToolOutputs(
      store,
      kind: OperationKind.convert,
      entries: [
        OutputEntry.bytes(
          bytes: converted,
          fileName: 'pixeltools_photo_1.tiff',
          publicKind: PublicFileKind.image,
        ),
      ],
    );
    expect(saved, isNotEmpty);
    final files = await outputs();
    // ignore: avoid_print
    print('CONVERT OUTPUT: ${files.map((f) => f.path).toList()}');
    expect(
      files.any((f) => f.path.toLowerCase().endsWith('.tiff')),
      isTrue,
    );
  });

  test('webp encode works', () async {
    final bytes = await File(imagePath).readAsBytes();
    final out = await PlatformImageEncoder.encodeWebP(bytes, quality: 90);
    expect(out, isNotNull);
  });
}
