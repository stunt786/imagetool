import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixeltools/core/models/operation_folder.dart';
import 'package:pixeltools/features/files/presentation/file_preview_screen.dart';
import 'package:pixeltools/features/files/widgets/file_edit_sheet.dart';
import 'package:pixeltools/shared/models/edit_history_item.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final testFileItem = AppFileItem(
    id: 'f1',
    operationId: 'op1',
    fileName: 'sample_photo.jpg',
    extension: 'jpg',
    mimeType: 'image/jpeg',
    path: '/mock/sample_photo.jpg',
    sizeBytes: 1024 * 500,
    createdAt: DateTime.now(),
    isPdf: false,
    isImage: true,
  );

  final testHistoryItem = EditHistoryItem(
    fileName: 'sample_photo.jpg',
    toolUsed: 'Crop & Resize',
    editedAt: DateTime.now(),
    filePath: '/mock/sample_photo.jpg',
  );

  group('FileEditSheet action button colors', () {
    testWidgets('renders dark mode with white and error colors', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: ThemeData.dark(),
            home: Scaffold(
              body: FileEditSheet(
                item: testFileItem,
                onDeleted: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // Find Text widgets for Share, Save, Rename, Delete
      final shareText = tester.widget<Text>(find.text('Share'));
      final saveText = tester.widget<Text>(find.text('Save'));
      final renameText = tester.widget<Text>(find.text('Rename'));
      final deleteText = tester.widget<Text>(find.text('Delete'));

      expect(shareText.style?.color, equals(Colors.white));
      expect(saveText.style?.color, equals(Colors.white));
      expect(renameText.style?.color, equals(Colors.white));
      expect(deleteText.style?.color, equals(const Color(0xFFFF5252)));

      // Check Icons
      final shareIcon = tester.widget<Icon>(find.byIcon(Icons.share_outlined));
      final saveIcon = tester.widget<Icon>(find.byIcon(Icons.download_outlined));
      final renameIcon = tester.widget<Icon>(find.byIcon(Icons.drive_file_rename_outline));
      final deleteIcon = tester.widget<Icon>(find.byIcon(Icons.delete_outline));

      expect(shareIcon.color, equals(Colors.white));
      expect(saveIcon.color, equals(Colors.white));
      expect(renameIcon.color, equals(Colors.white));
      expect(deleteIcon.color, equals(const Color(0xFFFF5252)));
    });

    testWidgets('renders light mode with onSurface and scheme.error colors (not white)', (tester) async {
      final lightTheme = ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.light,
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: lightTheme,
            home: Scaffold(
              body: FileEditSheet(
                item: testFileItem,
                onDeleted: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final onSurface = lightTheme.colorScheme.onSurface;
      final errorColor = lightTheme.colorScheme.error;

      // Find Text widgets for Share, Save, Rename, Delete
      final shareText = tester.widget<Text>(find.text('Share'));
      final saveText = tester.widget<Text>(find.text('Save'));
      final renameText = tester.widget<Text>(find.text('Rename'));
      final deleteText = tester.widget<Text>(find.text('Delete'));

      // They MUST NOT be Colors.white in light mode
      expect(shareText.style?.color, isNot(equals(Colors.white)));
      expect(saveText.style?.color, isNot(equals(Colors.white)));
      expect(renameText.style?.color, isNot(equals(Colors.white)));
      expect(deleteText.style?.color, isNot(equals(Colors.white)));

      expect(shareText.style?.color, equals(onSurface));
      expect(saveText.style?.color, equals(onSurface));
      expect(renameText.style?.color, equals(onSurface));
      expect(deleteText.style?.color, equals(errorColor));

      // Check Icons
      final shareIcon = tester.widget<Icon>(find.byIcon(Icons.share_outlined));
      final saveIcon = tester.widget<Icon>(find.byIcon(Icons.download_outlined));
      final renameIcon = tester.widget<Icon>(find.byIcon(Icons.drive_file_rename_outline));
      final deleteIcon = tester.widget<Icon>(find.byIcon(Icons.delete_outline));

      expect(shareIcon.color, equals(onSurface));
      expect(saveIcon.color, equals(onSurface));
      expect(renameIcon.color, equals(onSurface));
      expect(deleteIcon.color, equals(errorColor));
    });
  });

  group('FilePreviewScreen action button colors', () {
    testWidgets('renders light mode with onSurface and error colors (not hardcoded white)', (tester) async {
      final lightTheme = ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.light,
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: lightTheme,
            home: FilePreviewScreen(
              items: [testHistoryItem],
              initialIndex: 0,
            ),
          ),
        ),
      );
      await tester.pump();

      final onSurface = lightTheme.colorScheme.onSurface;
      final errorColor = lightTheme.colorScheme.error;

      // Find icons in bottom bar
      final saveIcon = tester.widget<Icon>(find.byIcon(Icons.save_alt_rounded));
      final renameIcon = tester.widget<Icon>(find.byIcon(Icons.edit_outlined).last);
      final shareIcon = tester.widget<Icon>(find.byIcon(Icons.share_rounded));
      final deleteIcon = tester.widget<Icon>(find.byIcon(Icons.delete_outline_rounded));

      expect(saveIcon.color, equals(onSurface));
      expect(renameIcon.color, equals(onSurface));
      expect(shareIcon.color, equals(onSurface));
      expect(deleteIcon.color, equals(errorColor));
    });

    testWidgets('renders PDF items with Export label properly colored in light mode', (tester) async {
      final pdfFileItem = AppFileItem(
        id: 'f2',
        operationId: 'op1',
        fileName: 'document.pdf',
        extension: 'pdf',
        mimeType: 'application/pdf',
        path: '/mock/document.pdf',
        sizeBytes: 1024 * 200,
        createdAt: DateTime.now(),
        isPdf: true,
      );

      final lightTheme = ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.light,
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: lightTheme,
            home: Scaffold(
              body: FileEditSheet(
                item: pdfFileItem,
                onDeleted: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final onSurface = lightTheme.colorScheme.onSurface;

      // Find 'Export' text instead of 'Save'
      final exportText = tester.widget<Text>(find.text('Export'));
      expect(exportText.style?.color, isNot(equals(Colors.white)));
      expect(exportText.style?.color, equals(onSurface));

      final exportIcon = tester.widget<Icon>(find.byIcon(Icons.download_outlined));
      expect(exportIcon.color, equals(onSurface));
    });
  });
}
