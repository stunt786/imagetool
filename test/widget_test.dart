// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:pixeltools/core/app/pixeltools_app.dart';

void main() {
  testWidgets('Home renders tool grid', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: PixelToolsApp()));
    await tester.pumpAndSettle();

    expect(find.text('PixelTools: Image & PDF Editor'), findsOneWidget);
    expect(find.text('Popular tools'), findsOneWidget);
    expect(find.text('Image Resizer'), findsOneWidget);
    expect(find.text('PDF Compressor'), findsOneWidget);
    expect(find.text('Tools'), findsOneWidget);
    expect(find.text('Images'), findsWidgets);
    expect(find.text('PDFs'), findsWidgets);
    expect(find.text('Settings'), findsOneWidget);
  });
}
