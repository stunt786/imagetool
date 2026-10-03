import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

Uint8List jpg(int w, int h) {
  final image = img.Image(width: w, height: h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      image.setPixelRgba(x, y, 200, 120, 60, 255);
    }
  }
  return Uint8List.fromList(img.encodeJpg(image));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('isolate run works in plain test', () async {
    final out = await Isolate.run(() => 41 + 1);
    expect(out, 42);
  });

  test('file io works in plain test', () async {
    final dir = await Directory.systemTemp.createTemp('probe_');
    final f = File('${dir.path}/a.jpg');
    await f.writeAsBytes(jpg(20, 20));
    expect(await f.readAsBytes(), isNotEmpty);
    await dir.delete(recursive: true);
  });

  testWidgets('file io works inside testWidgets via runAsync', (tester) async {
    Directory? dir;
    await tester.runAsync(() async {
      dir = await Directory.systemTemp.createTemp('probe2_');
      final f = File('${dir!.path}/a.jpg');
      await f.writeAsBytes(jpg(20, 20));
      expect(await f.readAsBytes(), isNotEmpty);
      await dir!.delete(recursive: true);
    });
    expect(dir, isNotNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('isolate run works inside testWidgets with runAsync',
      (tester) async {
    int? value;
    await tester.runAsync(() async {
      value = await Isolate.run(() => 7 * 6);
    });
    expect(value, 42);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('widget-internal file io without runAsync', (tester) async {
    final dir = await tester.runAsync(
        () => Directory.systemTemp.createTemp('probe3_'));
    final file = File('${dir!.path}/a.jpg')..writeAsBytesSync(jpg(20, 20));
    var done = false;
    await tester.pumpWidget(MaterialApp(
      home: StatefulBuilder(
        builder: (context, setState) => ElevatedButton(
          onPressed: () async {
            await file.readAsBytes();
            setState(() => done = true);
          },
          child: Text(done ? 'done' : 'go'),
        ),
      ),
    ));
    await tester.tap(find.text('go'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('done'), findsOneWidget);
    await dir.delete(recursive: true);
  });

  testWidgets('widget-internal file io with runAsync after tap',
      (tester) async {
    final dir = await tester.runAsync(
        () => Directory.systemTemp.createTemp('probe4_'));
    final file = File('${dir!.path}/a.jpg')..writeAsBytesSync(jpg(20, 20));
    var done = false;
    await tester.pumpWidget(MaterialApp(
      home: StatefulBuilder(
        builder: (context, setState) => ElevatedButton(
          onPressed: () async {
            await file.readAsBytes();
            setState(() => done = true);
          },
          child: Text(done ? 'done' : 'go'),
        ),
      ),
    ));
    await tester.tap(find.text('go'));
    await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('done'), findsOneWidget);
    await dir.delete(recursive: true);
  });

  testWidgets('image.memory renders synthetic jpeg', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Center(child: Image.memory(jpg(40, 40))),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(Image), findsOneWidget);
  });
}
