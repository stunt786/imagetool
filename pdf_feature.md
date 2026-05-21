Act as a Senior Flutter Developer & UI/UX Designer. Create a production-ready, cross-platform Flutter app (Android & iOS) with the following PDF utility features:

🔹 CORE FEATURES:
1. Compress PDF: Reduce file size while maintaining readability.
2. Merge PDFs: Combine 2+ PDFs into a single document with drag/drop reordering.
3. Split PDF: Extract specific pages or split into multiple files.
4. Convert PDF: Support conversion to JPG, PNG, and TXT. (Note: If DOCX conversion is not feasible natively in Flutter, implement a graceful fallback or document the limitation.)

🔹 UI/UX REQUIREMENTS:
- Modern, clean, card-based home screen with feature tiles.
- Dedicated screen for each feature with:
  • File picker integration (single/multi select)
  • Preview thumbnail grid for selected PDFs/pages
  • Settings/options (e.g., compression level, page range for split)
  • Progress indicator during processing
  • Success/Error snackbars with file path display
- Responsive layout (mobile & tablet friendly)
- Light/Dark mode support
- Use Material 3 design system

🔹 STORAGE & PERMISSIONS:
- All generated/processed files MUST be saved in the app-specific directory using `path_provider` (`getApplicationDocumentsDirectory()` or `getExternalStorageDirectory()` with proper fallbacks).
- Implement `permission_handler` for Android 13+ scoped storage and iOS document access.
- Provide clear UI feedback showing the exact saved file path and an "Open Folder" button.
- Include Android `AndroidManifest.xml` and iOS `Info.plist` permission configurations.

🔹 ARCHITECTURE & TECH STACK:
- Flutter 3.x, Dart 3.x (null-safe)
- State Management: Riverpod or Provider
- File Handling: `file_picker`, `path_provider`
- PDF Processing: `syncfusion_flutter_pdf` or `pdf` package (choose the most stable for native operations)
- UI: `flutter_riverpod`, `google_fonts`, `intl`, `cached_network_image` (if needed)
- Clean separation: `ui/`, `features/`, `core/`, `services/`, `utils/`

🔹 DELIVERABLES:
1. Complete `pubspec.yaml` with exact package versions
2. Full project structure with all Dart files
3. `main.dart` entry point with routing & theme
4. Feature-specific logic files with clear comments
5. Step-by-step setup & run instructions
6. Notes on platform-specific build configs (Android/iOS permissions, min SDK, etc.)

Write production-grade, well-commented code. Avoid placeholder logic. If a PDF operation requires native platform channels or heavy dependencies, clearly document how to integrate them and provide a working Dart fallback.,